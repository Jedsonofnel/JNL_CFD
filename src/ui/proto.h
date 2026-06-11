#ifndef JNL_UI_PROTO_H
#define JNL_UI_PROTO_H

#include <stddef.h>
#include "jnl/common.h"

//
// Message type bytes
//

typedef enum {
	JNL_UI_MSG_CLOSE = 0x01, // no payload
	JNL_UI_MSG_FOCUS = 0x02, // no payload

	JNL_UI_MSG_DOMAIN2D = 0x03,   // pre-sampled boundary chains
	JNL_UI_MSG_SET_MESH = 0x04,   // vertex/face/cell topology
	JNL_UI_MSG_SET_FIELD = 0x05,  // scalar field update
	JNL_UI_MSG_SET_VECTOR = 0x06, // associate two scalar fields as a vector
	JNL_UI_MSG_VIEW_FIELD = 0x07, // switch displayed overlay ("" = wireframe)
	JNL_UI_MSG_VIEW_MESH = 0x08,  // show/hide mesh wireframe
} jnl_ui_msg;

//
// Wire header structs (all little endian)
//

// MSG_DOMAIN2D — curve tree, child samples at its own resolution:
//   u8   type
//   u32  n_chains
//   [per chain: u8 kind, i32 marker, u8 name_len, u8 name[], serialized curve]
//
// Curve wire format (recursive):
//   u8  kind      (0=LINE 1=ARC 2=POLYLINE 3=CHAIN)
//   u8  reversed
//   LINE:     f64 x0,y0,x1,y1
//   ARC:      f64 cx,cy,r,theta0,theta1
//   POLYLINE: u32 n, f64 xy[n*2]
//   CHAIN:    u32 n, curve[n]  (recursive)
//
// kind values:
#define JNL_UI_CHAIN_OUTER 0x00
#define JNL_UI_CHAIN_PATCH 0x01
#define JNL_UI_CHAIN_HOLE 0x02

//
// Byte order primitives
//

#define JNL_W32(p, v)                                                          \
	do {                                                                       \
		(p)[0] = (u8)((v) & 0xff);                                             \
		(p)[1] = (u8)(((v) >> 8) & 0xff);                                      \
		(p)[2] = (u8)(((v) >> 16) & 0xff);                                     \
		(p)[3] = (u8)(((v) >> 24) & 0xff);                                     \
	} while (0)

#define JNL_R32(p)                                                             \
	((u32)(p)[0] | (u32)(p)[1] << 8 | (u32)(p)[2] << 16 | (u32)(p)[3] << 24)

//
// I/O primitives
//

int jnl_proto_send_all(int fd, const void *buf, size_t n);
int jnl_proto_recv_all(int fd, void *buf, size_t n);

#endif // JNL_UI_PROTO_H
