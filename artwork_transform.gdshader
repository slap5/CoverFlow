shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D art_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 atlas_scale = vec2(1.0);
uniform vec2 atlas_offset = vec2(0.0);
uniform vec2 image_scale = vec2(1.0);
void fragment() {
    vec2 local_uv = (UV - vec2(0.5)) / max(image_scale, vec2(0.01)) + vec2(0.5);
    if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThan(local_uv, vec2(1.0)))) { discard; }
    vec4 color = texture(art_texture, atlas_offset + local_uv * atlas_scale);
    ALBEDO = color.rgb;
    ALPHA = color.a;
}
