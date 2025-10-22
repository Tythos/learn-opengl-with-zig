# Learn OpenGL With Zig

This project is meant to provide a starting point for developers interested in learning how to use Zig to build OpenGL applications.

Specifically, this links against ZLM and SDL (for math, windowing, event, and context) to provide a basic "starter pack" from which developers can jump directly into exploration of quality content like the classic "LearnOpenGL" series:

https://learnopengl.com/Getting-started/Hello-Triangle

This version is built on Zig 0.12.1, which will be checked/enforced at build time. If you have cloned this project already, there is a basic three-step process to get going:

1. First, initialize the git submodules that hook in our two dependencies: `git submodule update --init`

1. Next, hand it off to Zig build: `zig build`

1. If the build was successful, you should be able to run the application and see a basic window & loop (press escape to quit): `zig build run`
