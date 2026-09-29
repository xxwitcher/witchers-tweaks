#version 440
// The genie minimize effect as a mesh warp (MinimizeEffect.qml): the window
// picture is a grid of rows; each row heads for the dock on its own schedule
// (the bottom ones first) and narrows as it goes down, so the window pours
// into the icon with its sides bending smoothly instead of in steps.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0: the window, 1: inside the dock
    vec4 fromRect;    // x, y, width, height of the window (this item's coordinates)
    vec4 toRect;      // the same for the dock spot
};

out gl_PerVertex { vec4 gl_Position; };

float smoother(float t) {
    t = clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

void main() {
    vec2 uv = qt_MultiTexCoord0;
    float lag = 0.55;
    float r = clamp(progress * (1.0 + lag) - (1.0 - uv.y) * lag, 0.0, 1.0);
    float y = mix(fromRect.y + uv.y * fromRect.w, toRect.y + uv.y * toRect.w, r * r);
    float span = toRect.y - fromRect.y;
    float f = span != 0.0 ? clamp((y - fromRect.y) / span, 0.0, 1.0) : 1.0;
    float s = smoother(f) * smoother(progress / 0.35);
    float w = mix(fromRect.z, toRect.z, s);
    float cx = mix(fromRect.x + fromRect.z * 0.5, toRect.x + toRect.z * 0.5, s);
    qt_TexCoord0 = uv;
    gl_Position = qt_Matrix * vec4(cx + (uv.x - 0.5) * w, y, 0.0, 1.0);
}
