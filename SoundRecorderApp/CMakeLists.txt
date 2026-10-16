# The app's QML plugin: the file work, the level meter and the encoder
# ranks (see the headers).
add_library(soundrecorder-qml MODULE
    plugin.cpp plugin.h
    fileoperations.cpp fileoperations.h
    levelmeter.cpp levelmeter.h
    audiopeak.cpp audiopeak.h
    encoderranks.cpp encoderranks.h
)

# So the plugin can be found next to its qmldir when running from the build tree.
file(COPY qmldir DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(soundrecorder-qml PRIVATE Qt6::Qml Qt6::Multimedia)

install(TARGETS soundrecorder-qml DESTINATION ${PLUGIN_DIR})
install(FILES qmldir DESTINATION ${PLUGIN_DIR})
