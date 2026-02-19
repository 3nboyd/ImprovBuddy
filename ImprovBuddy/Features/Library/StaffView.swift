import SwiftUI

struct StaffView: View {
    var notes: [StaffRenderedNote]
    var clef: TheoryClef

    private let lineSpacing: CGFloat = 14
    private let noteSpacing: CGFloat = 42
    private let baseCanvasHeight: CGFloat = 120
    private let clefX: CGFloat = 26
    private let staffLeftX: CGFloat = 44
    private let staffRightInset: CGFloat = 12
    private let noteStartX: CGFloat = 72

    private var canvasHeight: CGFloat {
        let highest = notes.map(\.staffStep).max() ?? 0
        let lowest = notes.map(\.staffStep).min() ?? 0
        let verticalSpan = CGFloat(max(abs(highest), abs(lowest)))
        let required = 2 * (verticalSpan + 5) * (lineSpacing / 2)
        return max(baseCanvasHeight, required)
    }

    private var canvasWidth: CGFloat {
        let count = max(notes.count, 1)
        return max(320, noteStartX + CGFloat(count - 1) * noteSpacing + 40)
    }

    private var clefSymbol: String {
        switch clef {
        case .treble: return "𝄞"
        case .alto: return "𝄡"
        case .bass: return "𝄢"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(clef.displayName + " Clef")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { context, size in
                    let centerY = size.height / 2
                    drawClef(context: &context, centerY: centerY)
                    drawStaffLines(context: &context, size: size, centerY: centerY)

                    for (index, note) in notes.enumerated() {
                        let x = noteStartX + CGFloat(index) * noteSpacing
                        let y = centerY - CGFloat(note.staffStep) * (lineSpacing / 2)

                        drawLedgerLines(context: &context, x: x, y: y, staffStep: note.staffStep, centerY: centerY)

                        let oval = CGRect(x: x - 7, y: y - 5, width: 14, height: 10)
                        context.fill(Path(ellipseIn: oval), with: .color(.primary))

                        if !note.spelled.accidental.isEmpty {
                            context.draw(
                                Text(note.spelled.accidental).font(.caption2.monospaced()),
                                at: CGPoint(x: x - 16, y: y - 2),
                                anchor: .center
                            )
                        }
                    }
                }
                .frame(
                    width: canvasWidth,
                    height: canvasHeight
                )
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func drawClef(context: inout GraphicsContext, centerY: CGFloat) {
        let y: CGFloat = switch clef {
        case .treble:
            centerY - lineSpacing
        case .alto:
            centerY
        case .bass:
            centerY + (lineSpacing * 0.4)
        }

        context.draw(
            Text(clefSymbol).font(.system(size: 44, weight: .regular, design: .serif)),
            at: CGPoint(x: clefX, y: y),
            anchor: .center
        )
    }

    private func drawStaffLines(context: inout GraphicsContext, size: CGSize, centerY: CGFloat) {
        for i in -2...2 {
            let y = centerY + CGFloat(i) * lineSpacing
            var path = Path()
            path.move(to: CGPoint(x: staffLeftX, y: y))
            path.addLine(to: CGPoint(x: size.width - staffRightInset, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
        }
    }

    private func drawLedgerLines(
        context: inout GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        staffStep: Int,
        centerY: CGFloat
    ) {
        let boundary = 4
        guard abs(staffStep) > boundary else { return }

        if staffStep > boundary {
            var step = boundary + 2
            while step <= staffStep {
                if step % 2 == 0 {
                    let yy = centerY - CGFloat(step) * (lineSpacing / 2)
                    var path = Path()
                    path.move(to: CGPoint(x: x - 11, y: yy))
                    path.addLine(to: CGPoint(x: x + 11, y: yy))
                    context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
                }
                step += 2
            }
            return
        }

        var step = -(boundary + 2)
        while step >= staffStep {
            if step % 2 == 0 {
                let yy = centerY - CGFloat(step) * (lineSpacing / 2)
                var path = Path()
                path.move(to: CGPoint(x: x - 11, y: yy))
                path.addLine(to: CGPoint(x: x + 11, y: yy))
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
            }
            step -= 2
        }
    }
}
