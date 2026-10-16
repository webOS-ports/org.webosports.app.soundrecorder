# Unit tests for the app's C++: the file operations, the peak of a buffer,
# the meter's fall-back and the encoder ranks. See README.md.
#
# Off by default, so image builds are unaffected:
#   cmake -DBUILD_TESTING=ON ...
# It needs googletest in the sysroot.

find_package(GTest REQUIRED)

add_executable(soundrecorder-tests
    unit/main.cpp
    unit/test_audiopeak.cpp
    unit/test_encoderranks.cpp
    unit/test_fileoperations.cpp
    unit/test_levelmeter.cpp
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/audiopeak.cpp
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/encoderranks.cpp
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/fileoperations.cpp
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/fileoperations.h
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/levelmeter.cpp
    ${PROJECT_SOURCE_DIR}/SoundRecorderApp/levelmeter.h
)
target_include_directories(soundrecorder-tests PRIVATE ${PROJECT_SOURCE_DIR}/SoundRecorderApp)
target_link_libraries(soundrecorder-tests PRIVATE GTest::gtest Qt6::Core Qt6::Multimedia)

add_test(NAME soundrecorder-unit COMMAND soundrecorder-tests)
