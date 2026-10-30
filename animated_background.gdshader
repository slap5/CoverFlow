shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D alley : source_color, filter_linear_mipmap;
void fragment() {
 vec2 p = SCREEN_UV;
 vec3 color = texture(alley, p).rgb;
 float mist = sin(p.x*9.0+TIME*0.06)*sin(p.y*8.0-TIME*0.035);
 float lamp = exp(-dot((p-vec2(0.60,0.08))*vec2(3.0,2.0),(p-vec2(0.60,0.08))*vec2(3.0,2.0))*6.0);
 ALBEDO = color * (0.92+0.025*mist) + vec3(0.02,0.012,0.004)*lamp*(0.5+0.5*sin(TIME*0.8));
}
