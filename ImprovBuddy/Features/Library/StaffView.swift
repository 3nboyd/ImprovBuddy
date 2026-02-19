import SwiftUI

struct StaffView: View {
    var notes: [StaffRenderedNote]
    var clef: TheoryClef

    private let lineSpacing: CGFloat = 14
    private let noteSpacing: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(clef.displayName + " Clef")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { context, size in
                    let centerY = size.height / 2
                    drawStaffLines(context: &context, size: size, centerY: centerY)

                    for (index, note) in notes.enumerated() {
                        let x = 28 + CGFloat(index) * noteSpacing
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
                .frame(width: max(280, CGFloat(notes.count) * noteSpacing + 64), height: 120)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func drawStaffLines(context: inout GraphicsContext, size: CGSize, centerY: CGFloat) {
        for i in -2...2 {
            let y = centerY + CGFloat(i) * lineSpacing
            var path = Path()
            path.move(to: CGPoint(x: 12, y: y))
            path.addLine(to: CGPoint(x: size.width - 12, y: y))
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
