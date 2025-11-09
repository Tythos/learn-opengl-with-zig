#version 330 core

struct Material {
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
    float shininess;
}; 

struct Light {
    vec3 position;
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

uniform vec3 objectColor;
uniform vec3 viewPos;
uniform Material material;
uniform Light light;
in vec3 Normal;
in vec3 FragPos;

out vec4 FragColor;

void main() {
    // compute ambient compoent
    float ambientStrength = 0.1;
    vec3 ambient = light.ambient * material.ambient;

    // compute diffuse compoent
    float diffuseStrength = 0.5;
    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(light.position - FragPos);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = light.diffuse * diff * material.diffuse;

    // compute specular component
    float specularStrength = 0.5;
    vec3 viewDir = normalize(viewPos - FragPos);
    vec3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), material.shininess);
    vec3 specular = light.specular * spec * material.specular;

    // blend output
    vec3 result = (
        ambient * ambientStrength
        + diffuse * diffuseStrength
        + specular * specularStrength
    ) * objectColor;
    FragColor = vec4(result, 1.0);
}
