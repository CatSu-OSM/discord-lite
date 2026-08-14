// Lion-safe replacement for libdave's modern Apple Keychain backend.
// The upstream implementation requires Security APIs newer than OS X 10.7.
#include "mls/detail/persisted_key_pair.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <dave/logger.h>
#include <mls/crypto.h>

namespace {

static bool makeDirectory(const std::string& path, bool requirePrivate) {
    if (mkdir(path.c_str(), S_IRWXU) == 0) return true;
    if (errno != EEXIST) return false;
    struct stat info;
    return stat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode) &&
      (!requirePrivate || (info.st_mode & 0077) == 0);
}

static std::string keyDirectory() {
    const char *home = getenv("HOME");
    if (!home || !*home) return std::string();
    const std::string library = std::string(home) + "/Library";
    const std::string applicationSupport = library + "/Application Support";
    const std::string directory = applicationSupport + "/Discord Lite Voice";
    if (!makeDirectory(library, false) || !makeDirectory(applicationSupport, false) ||
        !makeDirectory(directory, true)) return std::string();
    return directory;
}

static bool safeKeyName(const std::string& id) {
    if (id.empty() || id.size() > 200) return false;
    for (std::string::const_iterator it = id.begin(); it != id.end(); ++it) {
        const char c = *it;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
    }
    return true;
}

}

namespace discord {
namespace dave {
namespace mls {
namespace detail {

std::shared_ptr<::mlspp::SignaturePrivateKey> GetNativePersistedKeyPair(
  KeyPairContextType, const std::string&, ::mlspp::CipherSuite, bool& supported)
{
    supported = false;
    return nullptr;
}

std::shared_ptr<::mlspp::SignaturePrivateKey> GetGenericPersistedKeyPair(
  KeyPairContextType, const std::string& id, ::mlspp::CipherSuite suite)
{
    const std::string directory = keyDirectory();
    if (directory.empty() || !safeKeyName(id)) {
        DISCORD_LOG(LS_ERROR) << "Unable to create Lion DAVE key directory or key name";
        return nullptr;
    }
    const std::string path = directory + "/" + id + ".key";
    struct stat info;
    if (lstat(path.c_str(), &info) == 0) {
        if (!S_ISREG(info.st_mode) || (info.st_mode & 0077) != 0) {
            DISCORD_LOG(LS_ERROR) << "Refusing DAVE key with insecure permissions";
            return nullptr;
        }
        std::ifstream input(path.c_str(), std::ios::in | std::ios::binary);
        if (!input) return nullptr;
        const std::string serialized = (std::stringstream() << input.rdbuf()).str();
        try {
            return std::make_shared<::mlspp::SignaturePrivateKey>(
              ::mlspp::SignaturePrivateKey::from_jwk(suite, serialized));
        } catch (std::exception& error) {
            DISCORD_LOG(LS_ERROR) << "Could not read Lion DAVE key: " << error.what();
            return nullptr;
        }
    }
    if (errno != ENOENT) return nullptr;

    ::mlspp::SignaturePrivateKey key = ::mlspp::SignaturePrivateKey::generate(suite);
    const std::string serialized = key.to_jwk(suite);
    const std::string temporary = path + ".tmp-" + std::to_string((unsigned long)getpid());
    const int file = open(temporary.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR);
    if (file < 0) return nullptr;
    const ssize_t written = write(file, serialized.data(), serialized.size());
    const int closeResult = close(file);
    if (written != (ssize_t)serialized.size() || closeResult != 0 || rename(temporary.c_str(), path.c_str()) != 0) {
        unlink(temporary.c_str());
        return nullptr;
    }
    return std::make_shared<::mlspp::SignaturePrivateKey>(std::move(key));
}

bool DeleteNativePersistedKeyPair(KeyPairContextType, const std::string&) { return false; }

bool DeleteGenericPersistedKeyPair(KeyPairContextType, const std::string& id) {
    const std::string directory = keyDirectory();
    if (directory.empty() || !safeKeyName(id)) return false;
    return unlink((directory + "/" + id + ".key").c_str()) == 0;
}

} // namespace detail
} // namespace mls
} // namespace dave
} // namespace discord
