#ifndef COMMON_ALTRAITS_H
#define COMMON_ALTRAITS_H

namespace al {

template<typename T>
struct type_identity { using type = T; };

template<typename T>
using type_identity_t = typename type_identity<T>::type;

} // namespace al

#endif /* COMMON_ALTRAITS_H */
