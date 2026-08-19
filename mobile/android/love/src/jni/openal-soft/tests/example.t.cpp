#include <gtest/gtest.h>
#include <AL/al.h>

class ExampleTest : public ::testing::Test {
};


TEST_F(ExampleTest, Basic)
{
    // just making sure we compile
    ALuint source, buffer;
    ALfloat offset;
    ALenum state;
}


