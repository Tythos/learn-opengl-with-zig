#version 330 core
out vec4 FragColor;
  
in vec2 TexCoords;

uniform sampler2D screenTexture;
uniform int effect;  // 0=Normal, 1=Inversion, 2=Grayscale, 3=Sharpen, 4=Blur, 5=EdgeDetection

void main()
{ 
    vec3 color;
    
    if (effect == 0) {
        // Normal - passthrough
        color = texture(screenTexture, TexCoords).rgb;
    }
    else if (effect == 1) {
        // Inversion
        color = vec3(1.0) - texture(screenTexture, TexCoords).rgb;
    }
    else if (effect == 2) {
        // Grayscale (weighted)
        vec3 texColor = texture(screenTexture, TexCoords).rgb;
        float average = 0.2126 * texColor.r + 0.7152 * texColor.g + 0.0722 * texColor.b;
        color = vec3(average);
    }
    else if (effect >= 3 && effect <= 5) {
        // Kernel-based effects
        const float offset = 1.0 / 300.0;
        
        vec2 offsets[9] = vec2[](
            vec2(-offset,  offset), // top-left
            vec2( 0.0,     offset), // top-center
            vec2( offset,  offset), // top-right
            vec2(-offset,  0.0),    // center-left
            vec2( 0.0,     0.0),    // center-center
            vec2( offset,  0.0),    // center-right
            vec2(-offset, -offset), // bottom-left
            vec2( 0.0,    -offset), // bottom-center
            vec2( offset, -offset)  // bottom-right    
        );
        
        float kernel[9];
        
        if (effect == 3) {
            // Sharpen
            kernel = float[](
                -1, -1, -1,
                -1,  9, -1,
                -1, -1, -1
            );
        }
        else if (effect == 4) {
            // Blur
            kernel = float[](
                1.0 / 16, 2.0 / 16, 1.0 / 16,
                2.0 / 16, 4.0 / 16, 2.0 / 16,
                1.0 / 16, 2.0 / 16, 1.0 / 16
            );
        }
        else if (effect == 5) {
            // Edge detection
            kernel = float[](
                1,  1,  1,
                1, -8,  1,
                1,  1,  1
            );
        }
        
        vec3 sampleTex[9];
        for(int i = 0; i < 9; i++)
        {
            sampleTex[i] = vec3(texture(screenTexture, TexCoords.st + offsets[i]));
        }
        
        color = vec3(0.0);
        for(int i = 0; i < 9; i++)
            color += sampleTex[i] * kernel[i];
    }
    else {
        // Fallback to normal
        color = texture(screenTexture, TexCoords).rgb;
    }
    
    FragColor = vec4(color, 1.0);
}
