add_executable(OpenAL_Tests)

include(FetchContent)
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG        main
)
# For Windows: Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

target_link_libraries(OpenAL_Tests PRIVATE
	OpenAL
	GTest::gtest_main
)

target_sources(OpenAL_Tests PRIVATE
example.t.cpp
)

# This needs to come last
include(GoogleTest)
gtest_discover_tests(OpenAL_Tests)
