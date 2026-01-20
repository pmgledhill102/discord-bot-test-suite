cmake_minimum_required(VERSION 3.16)
project(discord-webhook-service CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(Drogon CONFIG REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SODIUM REQUIRED libsodium)

# Create executable
add_executable(server main.cc)

# Link libraries
target_link_libraries(server PRIVATE
    Drogon::Drogon
    ${SODIUM_LIBRARIES}
)

target_include_directories(server PRIVATE
    ${SODIUM_INCLUDE_DIRS}
)

# Install
install(TARGETS server DESTINATION bin)
