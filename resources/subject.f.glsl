#version 330 core
  
uniform vec3 objectColor;
uniform vec3 lightColor;
uniform vec3 lightPos;
uniform vec3 viewPos;
in vec3 Normal;
in vec3 FragPos;

out vec4 FragColor;

void main() {
    // compute ambient compoent
    float ambientStrength = 0.1;
    vec3 ambient = lightColor;

    // compute diffuse compoent
    float diffuseStrength = 0.5;
    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(lightPos - FragPos);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * lightColor;

    // compute specular component
    float specularStrength = 0.5;
    vec3 viewDir = normalize(viewPos - FragPos);
    vec3 reflectDir = reflect(-lightDir, norm);    
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = spec * lightColor;

    // blend output
    vec3 result = (
        ambient * ambientStrength
        + diffuse * diffuseStrength
        + specular * specularStrength
    ) * objectColor;
    FragColor = vec4(result, 1.0);
}
