// SPDX-License-Identifier: GPL-3.0-or-later
// Original GGGMac shader. SM 6.0/DXIL output is generated using Microsoft's DXC.
float4 vs_main(uint id : SV_VertexID) : SV_Position
{
    float2 position = id == 0 ? float2(-1, -1) :
                     (id == 1 ? float2(-1, 3) : float2(3, -1));
    return float4(position, 0, 1);
}

float4 ps_main() : SV_Target
{
    return float4(0.25, 0.5, 0.75, 1.0);
}
