"""The approved idle loop with hand-bound gear and planted-foot solves."""
import bpy, math
from mathutils import Vector, Matrix

def create_pose(arm, tail_bones, twohand):
    P, TWOHAND = "mixamorig:", twohand
    view = bpy.context.view_layer
    AWI = arm.matrix_world.to_3x3().normalized().inverted()
    pb = arm.pose.bones
    for p in pb:
        p.rotation_mode = "QUATERNION"
    BASE = {p.name: (p.rotation_quaternion.copy(), p.location.copy()) for p in pb}
    ARMS = ["LeftShoulder", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm"]
    ANIM = [P + n for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot",
                            "RightUpLeg", "RightLeg", "RightFoot"] + ([] if TWOHAND else ARMS)] + tail_bones
    UP, FWD, SIDE_AX = [(AWI @ Vector(v)).normalized() for v in ((0, 0, 1), (0, -1, 0), (1, 0, 0))]
    H_MODEL = 1.6


    def reset():
        for n in ANIM:
            pb[n].rotation_quaternion, pb[n].location = BASE[n][0].copy(), BASE[n][1].copy()
        view.update()


    def turn(name, axis, deg, move=None):
        p = pb[name]
        h = p.head.copy()
        m = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ p.matrix
        if move is not None:
            m = Matrix.Translation(move) @ m
        p.matrix = m
        view.update()


    def plateau(x, k):
        return math.tanh(k * x) / math.tanh(k)


    def bump(t, centre, power):
        return ((1.0 + math.cos(2 * math.pi * (t - centre))) / 2.0) ** power


    reset()
    LEGS = {s: {"H0": pb[P + s + "UpLeg"].head.copy(), "K0": pb[P + s + "Leg"].head.copy(),
                "A0": pb[P + s + "Foot"].head.copy(), "F0": pb[P + s + "Foot"].matrix.to_3x3().copy()} for s in ("Left", "Right")}


    def solve_leg(side):
        s = LEGS[side]
        up, leg, foot = pb[P + side + "UpLeg"], pb[P + side + "Leg"], pb[P + side + "Foot"]
        H, K = up.head.copy(), leg.head.copy()
        L1, L2 = (s["K0"] - s["H0"]).length, (s["A0"] - s["K0"]).length
        T = s["A0"]
        d = min(max((T - H).length, abs(L1 - L2) + 1e-4), L1 + L2 - 1e-4)
        u = (T - H).normalized()
        u0 = (s["A0"] - s["H0"]).normalized()
        n = (s["K0"] - s["H0"]) - (s["K0"] - s["H0"]).dot(u0) * u0
        w = (n - n.dot(u) * u).normalized()
        ca = (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d)
        Kn = H + L1 * (ca * u + math.sqrt(max(0.0, 1 - ca * ca)) * w)
        up.matrix = Matrix.Translation(H) @ (K - H).rotation_difference(Kn - H).to_matrix().to_4x4() @ Matrix.Translation(-H) @ up.matrix
        view.update()
        K = leg.head.copy()
        leg.matrix = Matrix.Translation(K) @ (foot.head - K).rotation_difference(T - K).to_matrix().to_4x4() @ Matrix.Translation(-K) @ leg.matrix
        view.update()
        foot.matrix = Matrix.Translation(foot.head.copy()) @ s["F0"].to_4x4()
        view.update()


    def pose_at(t):
        reset()
        breath = math.sin(2 * math.pi * 3 * t)
        weight = plateau(math.sin(2 * math.pi * t), 2.2)
        look = plateau(math.sin(2 * math.pi * t + 1.1), 2.5)
        lift = bump(t, 0.32, 6)
        shift = SIDE_AX * (0.018 * H_MODEL * weight) - UP * (0.004 * H_MODEL * abs(weight))
        turn(P + "Hips", FWD, 2.4 * weight, move=shift)
        turn(P + "Spine", FWD, -1.6 * weight)
        turn(P + "Spine1", FWD, -0.8 * weight)
        turn(P + "Spine1", SIDE_AX, -1.0 * breath)
        turn(P + "Spine2", SIDE_AX, -0.8 * breath)
        turn(P + "Neck", UP, 7.0 * look)
        turn(P + "Neck", FWD, -0.8 * weight)
        turn(P + "Head", UP, 11.0 * look)
        turn(P + "Head", SIDE_AX, 1.2 * breath - (0.0 if TWOHAND else 2.0 * lift))
        if not TWOHAND:
            turn(P + "LeftShoulder", FWD, 1.2 * breath)
            turn(P + "RightShoulder", FWD, -1.2 * breath)
            turn(P + "RightArm", SIDE_AX, -7.0 * lift)
            turn(P + "RightForeArm", SIDE_AX, -9.0 * lift)
            turn(P + "RightHand", SIDE_AX, -4.0 * lift)
            turn(P + "LeftArm", SIDE_AX, -1.0 * breath)
            turn(P + "LeftForeArm", UP, 1.5 * weight)
        for b, n in enumerate(tail_bones):
            turn(n, UP, -(3.0 + 1.5 * b) * math.sin(2 * math.pi * t - 0.6 - 0.35 * b) + 1.2 * math.sin(2 * math.pi * 3 * t - 0.5 * b))
            turn(n, SIDE_AX, 1.0 * math.sin(2 * math.pi * 2 * t - 0.4 * b))
        solve_leg("Left")
        solve_leg("Right")

    return ANIM, pose_at
