Shader "Yukatayu/Particle Network" {
	Properties {
		[Header(Particle)] [Space(7)]
		_TESS("粒子の量", Range(1, 64)) = 48
		_Size ("大きさ", Float) = 0.02
		_LatticeSpeed("上昇速度 (正の値)", Float) = 0.3
		_LatticeSize("並べる間隔", Float) = 0.06
		_LatticeCnt("横に並べる数", Int) = 15

		[Space(7)] [Header(Line)] [Space(7)]
		_LineLength("線を繋げる範囲", Range(0, 1)) = 0.8
		_LineWidthRate("線の幅", Range(0, 1)) = 0.5

		[Space(7)] [Header(Position)] [Space(7)]
		_Y_offset("高さ調整", Float) = 4
	}
	SubShader {
		Tags{ "RenderType" = "Transparent" "Queue" = "Transparent" }
		LOD 100
		Blend One One
		//Blend One OneMinusSrcAlpha
		ZWrite Off
		Cull Off

		Pass {
			CGPROGRAM
			#pragma target 5.0
			#pragma vertex mainVS
			#pragma hull mainHS
			#pragma domain mainDS
			#pragma geometry mainGS
			#pragma fragment mainFS

			#include "UnityCG.cginc"

			//#define TESS 48 // [Max 64] 連続&&一意なIDは64が限界っぽい

			float _Size;
			float _LatticeSpeed;
			float _LatticeSize;
			float _LineLength;
			float _Y_offset;
			float _LineWidthRate;
			int _LatticeCnt;
			int _TESS;

			// Struct
			struct VS_IN {
				float4 pos   : POSITION;
			};

			struct VS_OUT {
				float4 pos    : POSITION;
			};

			struct CONSTANT_HS_OUT {
				float Edges[4] : SV_TessFactor;
				float Inside[2] : SV_InsideTessFactor;
			};

			struct HS_OUT {
			};

			struct DS_OUT {
				uint pid : PID;	// GeometryShaderに実行用の一意連続なIDを発行する
			};

			struct GS_OUT {
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 color : COLOR0;
				float2 type : TEXCOORD1;
			};

			// Utility
			float3 rand3(float3 p) {
				p = float3( dot(p,float3(127.1, 311.7, 74.7)),
							dot(p,float3(269.5, 183.3,246.1)),
							dot(p,float3(113.5,271.9,124.6)));
				return frac(sin(p)*43758.5453123);
			}
			float rand(float x, float y) {
				return frac(sin(dot(float2(x, y), float2(12.9898, 78.233))) * 43758.5453);
			}

			float3 HUEtoRGB(in float H) {
				float R = abs(H * 6 - 3) - 1;
				float G = 2 - abs(H * 6 - 2);
				float B = 2 - abs(H * 6 - 4);
				return saturate(float3(R,G,B));
			}
			float3 HSVtoRGB(in float3 HSV){
				float3 RGB = HUEtoRGB(HSV.x);
				return ((RGB - 1) * HSV.y + 1) * HSV.z;
			}

			// Main
			VS_OUT mainVS(VS_IN In) {
				VS_OUT Out;
				Out.pos = In.pos;
				return Out;
			}

			CONSTANT_HS_OUT mainCHS() {
				CONSTANT_HS_OUT Out;

				int t = _TESS + 1;
				Out.Edges[0] = t;
				Out.Edges[1] = t;
				Out.Edges[2] = t;
				Out.Edges[3] = t;
				Out.Inside[0] = t;
				Out.Inside[1] = t;

				return Out;
			}

			[domain("quad")]
			[partitioning("pow2")]
			[outputtopology("point")]
			[outputcontrolpoints(4)]
			[patchconstantfunc("mainCHS")]
			HS_OUT mainHS() {
			}

			[domain("quad")]
			DS_OUT mainDS(CONSTANT_HS_OUT In, const OutputPatch<HS_OUT, 4> patch, float2 uv : SV_DomainLocation) {
				DS_OUT Out;
				Out.pid = (uint)(uv.x * _TESS) + ((uint)(uv.y * _TESS) * _TESS);
				return Out;
			}

			inline float3 latticePointPos(float3 lattice_xyz){
				lattice_xyz += rand3(lattice_xyz);
				lattice_xyz.y -= _Time.y * _LatticeSpeed;
				lattice_xyz.xz -= 0.5 * _LatticeCnt;
				lattice_xyz.y -= _LatticeSize * _Y_offset;
				lattice_xyz.y *= -1;
				return lattice_xyz;
			}

			inline float3 latticePointColor(float3 lattice){
				return HSVtoRGB(
					float3(
						rand(lattice.y, rand(lattice.x, lattice.z)),
						rand(lattice.z, rand(lattice.y, lattice.x)) * 0.05 + 0.95,
						rand(lattice.x, rand(lattice.z, lattice.y)) * 0.4 + 0.6
					)) * saturate((-latticePointPos(lattice).y+_LatticeSize * _Y_offset)/_LatticeSize);
			}

			#define ADD_VERT(u, v) \
				o.uv = float2(u, v); \
				o.vertex = vert + float4(u*ar, v, 0, 0)*_Size; \
				outStream.Append(o);

			#define ADD_LINE_VERT(u, v) \
				o.uv = float2(u, v); \
				o.vertex = vert + u*dir1 + (v-0.5)*dir2; \
				outStream.Append(o);

			inline float4 posToClip(float3 xyz){
				return UnityObjectToClipPos(float4(xyz, 1));
			}

			[maxvertexcount(81)]
			void mainGS(point DS_OUT input[1], inout TriangleStream<GS_OUT> outStream) {

				GS_OUT o;
				DS_OUT v = input[0];
				uint id = v.pid;  // 一意なid
				float ar = - UNITY_MATRIX_P[0][0] / UNITY_MATRIX_P[1][1]; //Aspect Ratio

				// 今表示されている格子は、 floor(_Time.y/_LatticeSpeed)から表示開始
				// _LatticeCnt^2 の格子に詰めていく
				uint floorOffset = floor(_Time.y * _LatticeSpeed);
				uint floorCnt = _LatticeCnt * _LatticeCnt;

				int3 lattice = int3(0, floorOffset + id / floorCnt, 0);
				uint lattice_xz = id % floorCnt;
				lattice.x = lattice_xz / _LatticeCnt;
				lattice.z = lattice_xz % _LatticeCnt;

				float3 latticePos = latticePointPos(lattice);  // 頂点のローカル座標
				float4 vert = posToClip(latticePos * _LatticeSize);

				// 三角形
				o.type = float2(0, 1);
				float3 latticeCol = latticePointColor(lattice);
				o.color = float4(latticeCol, 1);
				ADD_VERT(0.0, 1.0);
				ADD_VERT(-0.9, -0.5);
				ADD_VERT(0.9, -0.5);
				outStream.RestartStrip();

				// 四角形
				o.type = float2(1, 1);
				for(int i=0; i<13; ++i){
					// 近傍探索
					int ig = i + 5;
					int3 neighbor_xyz = lattice + int3(
						(ig / 3) % 3 - 1,
						(ig / 9),
						ig % 3 - 1
					);

					float3 neighborLatticePos = latticePointPos(neighbor_xyz);
					float3 neighborLatticeCol = latticePointColor(neighbor_xyz);
					if(length(latticePos - neighborLatticePos) < _LineLength){
						float4 dir1 = posToClip(neighborLatticePos * _LatticeSize) - vert;
						float4 dir2 = float4(normalize(float3(-dir1.y, dir1.x, 0)) * _Size * _LineWidthRate, 0);
						//dir1.w = dir2.w = 0;

						o.color = float4(latticeCol, 1);
						ADD_LINE_VERT(0, 1);
						ADD_LINE_VERT(0, 0);
						o.color = float4(neighborLatticeCol, 1);
						ADD_LINE_VERT(1, 0);
						outStream.RestartStrip();

						ADD_LINE_VERT(1, 0);
						ADD_LINE_VERT(1, 1);
						o.color = float4(latticeCol, 1);
						ADD_LINE_VERT(0, 1);
						outStream.RestartStrip();
					}
				}

			}

			float4 mainFS(GS_OUT i) : SV_Target {
				float4 col = i.color;
				//col.rgb *= (abs(i.uv.x) < 0.9) * (abs(i.uv.y) < 0.9);
				if(i.type.x < 0.5){ // type.x = 0 -> 三角形
					float4 res = saturate(.5-length(i.uv)) * clamp(col / pow(length(i.uv), 2), 0, 2);
					return res;
				}else{  // type.x = 1 -> 四角形
					col = saturate(
							col
							* (saturate(pow(saturate(0.5-abs(i.uv.y-0.5) + 0.4), 4) * 1.5)  // 長辺
							+ pow((0.5-abs(i.uv.y-0.5))*2, 9)) // 真ん中を白く
						) * saturate((0.5-abs(i.uv.x-0.5)) * 10); // 短辺;
				}
				return col;
			}
				ENDCG
		}
	}
}
