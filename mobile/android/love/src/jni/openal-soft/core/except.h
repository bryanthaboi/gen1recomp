#ifndef CORE_EXCEPT_H
#define CORE_EXCEPT_H

#include <cstdarg>
#include <exception>
#include <string>
#include <utility>


namespace al {

class base_exception : public std::exception {
    std::string mMessage;

protected:
    auto setMessage(const char *msg, std::va_list args) -> void;

public:
    base_exception() = default;
    base_exception(const base_exception&) = default;
    base_exception(base_exception&&) = default;
    ~base_exception() override;

    auto operator=(const base_exception&) -> base_exception& = default;
    auto operator=(base_exception&&) -> base_exception& = default;

    [[nodiscard]] auto what() const noexcept -> const char* override { return mMessage.c_str(); }
};

} // namespace al

#endif /* CORE_EXCEPT_H */
