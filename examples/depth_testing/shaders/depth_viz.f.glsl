#version 330 core
out vec4 FragColor;

void main()
{
    // Output the non-linear depth value directly
    FragColor = vec4(vec3(gl_FragCoord.z), 1.0);
}
