#include <iostream>
#include <thread>
#include <chrono>

int main() {
    std::cout << "Demo app starting..." << std::endl;
    // Sleep so we can attach to it
    for (int i = 0; i < 30; ++i) {
        std::cout << "tick " << i << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    std::cout << "Demo app exiting." << std::endl;
    return 0;
}
