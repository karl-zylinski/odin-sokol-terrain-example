@header package game
@header import sg "sokol/gfx"

@ctype mat4 Mat4

@vs vs
uniform vs_params {
    mat4 mvp;
    float time;
};

uniform texture2D tex;
uniform sampler smp;

layout(location=0) in vec4 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec4 color0;

out vec4 color;
out vec2 uv;
out float height;

void main() {
    uv = texcoord;
    float h = texture(sampler2D(tex, smp), texcoord).r;
    gl_Position = mvp * position;
    height = h;
    color = vec4(h,h,h,1);
    gl_Position.y += h*30;
}
@end

@fs fs

in vec4 color;
in vec2 uv;
in float height;
out vec4 frag_color;

void main() {
    frag_color = clamp(vec4(0.3, 0.6, 0.3, 1) * color + vec4(0, 0.1, 0, 0), 0, 1);
}
@end

@program cube vs fs
