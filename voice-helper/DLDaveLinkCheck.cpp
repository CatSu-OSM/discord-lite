// Standalone 10.7+ DAVE helper link check. The main app remains 10.6-targeted.
#include <dave/dave.h>
#include <exception>
#include <stdio.h>

// libdave is compiled with a newer libc++ that has std::variant. Xcode 4's
// Lion libc++ predates it, so supply the ABI symbols needed by that library.
namespace std {
class bad_variant_access : public exception {
public:
    bad_variant_access() throw();
    virtual ~bad_variant_access() throw();
    virtual const char *what() const throw();
};

bad_variant_access::bad_variant_access() throw() {}
bad_variant_access::~bad_variant_access() throw() {}
const char *bad_variant_access::what() const throw() { return "bad variant access"; }

inline namespace __1 {
void __throw_bad_variant_access() { throw bad_variant_access(); }
}
}

int main() {
    printf("DAVE maximum protocol version: %u\n", daveMaxSupportedProtocolVersion());
    return 0;
}
