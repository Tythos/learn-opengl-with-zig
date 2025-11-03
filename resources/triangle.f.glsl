#version 330 core
out vec4 FragColor;
uniform float some_uniform;

void main() {
    FragColor = vec4(0.0, some_uniform, 0.0, 1.0);
}
