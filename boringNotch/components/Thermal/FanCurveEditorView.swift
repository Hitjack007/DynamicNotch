//
//  FanCurveEditorView.swift
//  boringNotch
//

import SwiftUI
import Defaults

struct FanCurveEditorView: View {
    @Default(.fanCurvePoints) var points

    @State private var draggingIdx: Int? = nil

    private let iL: CGFloat = 40
    private let iR: CGFloat = 12
    private let iT: CGFloat = 14
    private let iB: CGFloat = 28
    private let minTemp: CGFloat = 40
    private let maxTemp: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            let sz = geo.size
            ZStack(alignment: .topLeading) {
                // Canvas: zones, grid, gradient fill, curve
                Canvas { ctx, cSz in
                    drawZones(ctx, size: cSz)
                    drawGrid(ctx, size: cSz)
                    drawFill(ctx, size: cSz)
                    drawCurve(ctx, size: cSz)
                }
                .frame(width: sz.width, height: sz.height)

                // Transparent tap target for adding points — sits below drag handles
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onEnded { val in
                                guard hypot(val.translation.width, val.translation.height) < 5 else { return }
                                let loc = val.location
                                let nearHandle = sorted.contains { pt in
                                    hypot(loc.x - xPos(CGFloat(pt.tempC), in: sz),
                                          loc.y - yPos(CGFloat(pt.fanPercent), in: sz)) < 16
                                }
                                guard !nearHandle else { return }
                                addPoint(at: loc, in: sz)
                            }
                    )

                // Y-axis labels
                ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                    Text("\(pct)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(.secondaryLabelColor))
                        .position(x: iL / 2, y: yPos(CGFloat(pct), in: sz))
                }

                // X-axis labels
                ForEach([40, 55, 70, 85, 100], id: \.self) { temp in
                    Text("\(temp)°")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabelColor))
                        .position(x: xPos(CGFloat(temp), in: sz), y: sz.height - iB / 2)
                }

                // Drag handles — listed after tap target so they take gesture priority
                ForEach(Array(points.enumerated()), id: \.element.id) { idx, pt in
                    dragHandle(idx: idx, pt: pt, in: sz)
                }

                // Max-points badge
                if points.count >= 5 {
                    Text("5 / 5")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                        .position(x: sz.width - iR - 22, y: iT + 9)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Coordinate helpers

    private func xPos(_ temp: CGFloat, in sz: CGSize) -> CGFloat {
        iL + (temp - minTemp) / (maxTemp - minTemp) * (sz.width - iL - iR)
    }

    private func yPos(_ pct: CGFloat, in sz: CGSize) -> CGFloat {
        iT + (1 - pct / 100) * (sz.height - iT - iB)
    }

    private func tempAt(x: CGFloat, in sz: CGSize) -> Int {
        let t = (x - iL) / (sz.width - iL - iR)
        let raw = minTemp + t * (maxTemp - minTemp)
        return snapValue(Int(raw.rounded()), step: 5, lo: Int(minTemp), hi: Int(maxTemp))
    }

    private func pctAt(y: CGFloat, in sz: CGSize) -> Int {
        let t = 1 - (y - iT) / (sz.height - iT - iB)
        return snapValue(Int((t * 100).rounded()), step: 5, lo: 0, hi: 100)
    }

    private func snapValue(_ v: Int, step: Int, lo: Int, hi: Int) -> Int {
        Swift.min(hi, Swift.max(lo, Int((Double(v) / Double(step)).rounded()) * step))
    }

    private var sorted: [FanCurvePoint] {
        points.sorted { $0.tempC < $1.tempC }
    }

    // MARK: - Drawing

    private func drawZones(_ ctx: GraphicsContext, size: CGSize) {
        let zones: [(lo: CGFloat, hi: CGFloat, color: Color)] = [
            (40, 65, Color(red: 0.35, green: 0.65, blue: 1.0)),
            (65, 80, Color(red: 1.0, green: 0.78, blue: 0.25)),
            (80, 100, Color(red: 1.0, green: 0.38, blue: 0.2)),
        ]
        for z in zones {
            let x1 = xPos(z.lo, in: size)
            let x2 = xPos(z.hi, in: size)
            let rect = CGRect(x: x1, y: iT, width: x2 - x1, height: size.height - iT - iB)
            ctx.fill(Path(rect), with: .color(z.color.opacity(0.05)))
        }
    }

    private func drawGrid(_ ctx: GraphicsContext, size: CGSize) {
        for t in stride(from: 40, through: 100, by: 10) {
            let x = xPos(CGFloat(t), in: size)
            var p = Path()
            p.move(to: CGPoint(x: x, y: iT))
            p.addLine(to: CGPoint(x: x, y: size.height - iB))
            ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
        }
        for pct in stride(from: 0, through: 100, by: 25) {
            let y = yPos(CGFloat(pct), in: size)
            var p = Path()
            p.move(to: CGPoint(x: iL, y: y))
            p.addLine(to: CGPoint(x: size.width - iR, y: y))
            let opacity: Double = (pct == 0 || pct == 100) ? 0.15 : 0.08
            ctx.stroke(p, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
        }
    }

    private func drawFill(_ ctx: GraphicsContext, size: CGSize) {
        let sp = sorted
        guard sp.count >= 2 else { return }
        var fill = Path()
        let bottom = size.height - iB
        fill.move(to: CGPoint(x: xPos(CGFloat(sp[0].tempC), in: size), y: bottom))
        for pt in sp {
            fill.addLine(to: CGPoint(x: xPos(CGFloat(pt.tempC), in: size),
                                     y: yPos(CGFloat(pt.fanPercent), in: size)))
        }
        fill.addLine(to: CGPoint(x: xPos(CGFloat(sp.last!.tempC), in: size), y: bottom))
        fill.closeSubpath()
        ctx.fill(fill, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 1.0, green: 0.55, blue: 0.0, opacity: 0.28), location: 0),
                .init(color: Color(red: 1.0, green: 0.55, blue: 0.0, opacity: 0.0), location: 1),
            ]),
            startPoint: CGPoint(x: size.width / 2, y: iT),
            endPoint: CGPoint(x: size.width / 2, y: bottom)
        ))
    }

    private func drawCurve(_ ctx: GraphicsContext, size: CGSize) {
        let sp = sorted
        guard sp.count >= 2 else { return }
        var path = Path()
        path.move(to: CGPoint(x: xPos(CGFloat(sp[0].tempC), in: size),
                              y: yPos(CGFloat(sp[0].fanPercent), in: size)))
        for pt in sp.dropFirst() {
            path.addLine(to: CGPoint(x: xPos(CGFloat(pt.tempC), in: size),
                                     y: yPos(CGFloat(pt.fanPercent), in: size)))
        }
        // Soft glow behind the main line
        ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.55, blue: 0.0, opacity: 0.22)),
                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        // Main curve
        ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.62, blue: 0.12, opacity: 0.95)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Drag handle

    @ViewBuilder
    private func dragHandle(idx: Int, pt: FanCurvePoint, in sz: CGSize) -> some View {
        let isDragging = draggingIdx == idx
        let color = handleColor(for: pt.tempC)
        ZStack {
            if isDragging {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 28, height: 28)
            }
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.88), lineWidth: 1.5))
                .shadow(color: color.opacity(isDragging ? 0.75 : 0.35),
                        radius: isDragging ? 7 : 3)
            if isDragging {
                Text("\(pt.tempC)°C · \(pt.fanPercent)%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.78)))
                    .offset(y: pt.fanPercent > 65 ? 26 : -26)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .position(x: xPos(CGFloat(pt.tempC), in: sz), y: yPos(CGFloat(pt.fanPercent), in: sz))
        .animation(.spring(duration: 0.15), value: isDragging)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if draggingIdx != idx { draggingIdx = idx }
                    guard points.indices.contains(idx) else { return }
                    let newT = tempAt(x: v.location.x, in: sz)
                    let newP = pctAt(y: v.location.y, in: sz)
                    let occupied = points.indices.filter { $0 != idx }.map { points[$0].tempC }
                    if !occupied.contains(newT) { points[idx].tempC = newT }
                    points[idx].fanPercent = newP
                }
                .onEnded { _ in draggingIdx = nil }
        )
        .contextMenu {
            if points.count > 2 {
                Button("Remove point", role: .destructive) {
                    points.remove(at: idx)
                }
            }
        }
    }

    private func handleColor(for tempC: Int) -> Color {
        switch tempC {
        case ..<60:  return Color(red: 0.42, green: 0.72, blue: 1.0)
        case ..<75:  return Color(red: 1.0, green: 0.80, blue: 0.22)
        default:     return Color(red: 1.0, green: 0.45, blue: 0.15)
        }
    }

    // MARK: - Add point (max 5)

    private func addPoint(at loc: CGPoint, in sz: CGSize) {
        guard points.count < 5 else { return }
        guard loc.x >= iL, loc.x <= sz.width - iR,
              loc.y >= iT, loc.y <= sz.height - iB else { return }
        let t = tempAt(x: loc.x, in: sz)
        let p = pctAt(y: loc.y, in: sz)
        guard !points.map(\.tempC).contains(t) else { return }
        points.append(FanCurvePoint(tempC: t, fanPercent: p))
    }
}
