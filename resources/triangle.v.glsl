#version 330 compatibility

layout (location = 0) in vec3 aPos;

void main() {
    vec2 vect = vec2(0.5, 0.7);
    vec4 result = vec4(vect, 0.0, 0.0);
    vec4 otherResult = vec4(result.xyz, 1.0);
    gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
}
