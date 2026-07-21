brew install cmake molten-vk vulkan-headers vulkan-loader glslang shaderc llvm libomp

# Configura o CMake apontando para o LLVM do Homebrew
cmake -DCMAKE_C_COMPILER=$(brew --prefix llvm)/bin/clang \
      -DCMAKE_CXX_COMPILER=$(brew --prefix llvm)/bin/clang++ \
      -B build -DGGML_VULKAN=ON
cmake --build build --config Release