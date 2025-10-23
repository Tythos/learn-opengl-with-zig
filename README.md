# Learn OpenGL With Zig

This project is meant to provide a starting point for developers interested in learning how to use Zig to build OpenGL applications.

Specifically, this links against ZLM and SDL (for math, windowing, event, and context) to provide a basic "starter pack" from which developers can jump directly into exploration of quality content like the classic "LearnOpenGL" series:

https://learnopengl.com/Getting-started/Hello-Triangle

This version is built on Zig 0.12.1, which will be checked/enforced at build time. If you have cloned this project already, there is a basic three-step process to get going:

1. First, initialize the git submodules that hook in our two dependencies: `git submodule update --init`

1. Next, hand it off to Zig build: `zig build`

1. If the build was successful, you should be able to run the application and see a basic window & loop (press escape to quit): `zig build run`

## Subsections

The `LearnOpenGL` curriculum is based around 7-8 sections (depending on if you count guest articles), beginning with "Getting Started". So as not to "spoil" too much, I have left most of the main branch on where you would start from the end of "Getting Started - Hello Window". But there are tagged branches for the conclusion of each subsection (as I am working through most of them myself), that I will link here for convenience:

* [Getting Started - Hello Triangle](https://github.com/Tythos/learn-opengl-with-zig/tree/getting-started--hello-triangle)
