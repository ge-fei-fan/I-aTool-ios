import SwiftUI

struct HomeView: View {
    @State private var screen: FitnessScreen = .mine
    @State private var feedbackMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            FitnexColor.background.ignoresSafeArea()

            switch screen {
            case .mine:
                MinePageView(
                    openActivity: { screen = .activity },
                    feedback: feedback
                )
            case .activity:
                ActivityStatusView(
                    back: { screen = .mine },
                    feedback: feedback
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(FitnexColor.black.opacity(0.88), in: Capsule())
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: screen)
        .animation(.easeInOut(duration: 0.18), value: feedbackMessage)
    }

    private func feedback(_ message: String) {
        feedbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if feedbackMessage == message {
                feedbackMessage = nil
            }
        }
    }
}

private enum FitnessScreen {
    case mine
    case activity
}

private enum FitnexColor {
    static let background = Color.white
    static let black = Color(hex: 0x111111)
    static let orange = Color(hex: 0xFE6F32)
    static let orangeSoft = Color(hex: 0xFFF0E9)
    static let grayText = Color(hex: 0x888888)
    static let lightText = Color(hex: 0xAAAAAA)
    static let border = Color(hex: 0xDDDDDD)
    static let card = Color.white
    static let pale = Color(hex: 0xF7F7F7)
}

private struct MinePageView: View {
    let openActivity: () -> Void
    let feedback: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    mineHeader

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("January 28,2023")
                                    .font(.fitnexBody(size: 11, weight: .regular))
                                    .foregroundColor(FitnexColor.grayText)
                                Text("Today’s Information")
                                    .font(.fitnexTitle(size: 15))
                                    .foregroundColor(FitnexColor.black)
                            }
                            Spacer()
                            Button {
                                feedback("More options")
                            } label: {
                                Image(systemName: "ellipsis")
                                    .rotationEffect(.degrees(90))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(FitnexColor.black)
                                    .frame(width: 32, height: 32)
                            }
                        }

                        DayStrip()
                    }

                    Button(action: openActivity) {
                        ChallengeCard()
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: [
                        GridItem(.fixed(155), spacing: 15),
                        GridItem(.fixed(155), spacing: 15)
                    ], alignment: .leading, spacing: 15) {
                        MetricCard(
                            title: "Calories",
                            value: "30.34 Kcal",
                            icon: "flame.fill",
                            style: .miniBars
                        )
                        .onTapGesture(perform: openActivity)

                        MetricCard(
                            title: "Steps",
                            value: "1409 steps",
                            icon: "figure.walk",
                            style: .steps
                        )
                        .onTapGesture(perform: openActivity)

                        HeartCard()
                            .onTapGesture(perform: openActivity)

                        MetricCard(
                            title: "Weight",
                            value: "56.5 kg",
                            subtitle: "Regular records",
                            icon: "dumbbell.fill",
                            style: .weight
                        )
                    }

                    InviteCard()
                        .onTapGesture { feedback("Invite flow") }

                    Spacer(minLength: 105)
                }
                .padding(.horizontal, 25)
                .padding(.top, 44)
            }

            FitnexTabBar(selected: .profile, openActivity: openActivity, feedback: feedback)
        }
    }

    private var mineHeader: some View {
        HStack(spacing: 12) {
            ProfileAvatar(size: 50)

            Text("Hello Hasan,\nReady for challenge?")
                .font(.fitnexTitle(size: 18))
                .foregroundColor(FitnexColor.black)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                feedback("Notifications")
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FitnexColor.lightText, lineWidth: 1)
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(FitnexColor.grayText)
                    Circle()
                        .fill(FitnexColor.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: -10, y: 10)
                }
                .frame(width: 40, height: 40)
            }
        }
    }
}

private struct ActivityStatusView: View {
    let back: () -> Void
    let feedback: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ActivityTopBar(back: back, feedback: feedback)
                    .padding(.top, 44)

                HStack(spacing: 15) {
                    ActivityRingCard(title: "Walk", value: "1409", unit: "steps", icon: "figure.walk", progress: 0.63)
                    ActivityRingCard(title: "Sleep", value: "8HR", unit: "20 sce", icon: "moon.fill", progress: 0.52)
                }
                .padding(.top, 40)

                HStack(alignment: .center) {
                    Text("Working Progress")
                        .font(.fitnexTitle(size: 15))
                        .foregroundColor(FitnexColor.black)
                    Spacer()
                    Button {
                        feedback("Weekly filter")
                    } label: {
                        HStack(spacing: 7) {
                            Text("Weekly")
                                .font(.fitnexBody(size: 11, weight: .regular))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundColor(FitnexColor.orange)
                        .frame(width: 70, height: 25)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(FitnexColor.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.top, 30)

                ProgressChart()
                    .frame(height: 190)
                    .padding(.top, 18)

                HStack {
                    Text("Latest Workout")
                        .font(.fitnexTitle(size: 15))
                        .foregroundColor(FitnexColor.black)
                    Spacer()
                    Button("See All") {
                        feedback("Workout list")
                    }
                    .font(.fitnexBody(size: 11, weight: .regular))
                    .foregroundColor(FitnexColor.orange)
                }
                .padding(.top, 28)

                VStack(spacing: 15) {
                    WorkoutRow(
                        title: "Full Body",
                        detail: "150 Calories burn | 20 min",
                        symbol: "figure.strengthtraining.traditional"
                    )
                    WorkoutRow(
                        title: "AB Workout",
                        detail: "180 Calories burn | 15 min",
                        symbol: "figure.core.training"
                    )
                }
                .padding(.top, 15)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 25)
        }
        .background(FitnexColor.background)
    }
}

private struct ActivityTopBar: View {
    let back: () -> Void
    let feedback: (String) -> Void

    var body: some View {
        HStack {
            SquareIconButton(systemName: "chevron.left", action: back)
            Spacer()
            Text("Activity Status")
                .font(.fitnexTitle(size: 18))
                .foregroundColor(FitnexColor.black)
            Spacer()
            SquareIconButton(systemName: "bell", action: { feedback("Notifications") }, dot: true)
        }
        .frame(height: 35)
    }
}

private struct DayStrip: View {
    private let days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                Text(day)
                    .font(.fitnexBody(size: 11, weight: .regular))
                    .foregroundColor(day == "THU" ? .white : FitnexColor.grayText)
                    .frame(width: day == "THU" ? 40 : 48, height: 20)
                    .background {
                        if day == "THU" {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(FitnexColor.orange)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChallengeCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(FitnexColor.orangeSoft)
                Image(systemName: "figure.walk")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(FitnexColor.orange)
            }
            .frame(width: 50, height: 50)

            Text("New Challenge 🔥\n5000 Steps")
                .font(.fitnexTitle(size: 16))
                .foregroundColor(FitnexColor.black)
                .lineSpacing(2)

            Spacer()

            Circle()
                .fill(FitnexColor.orangeSoft)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FitnexColor.orange)
                }
        }
        .padding(.horizontal, 15)
        .frame(height: 80)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private enum MetricChartStyle {
    case miniBars
    case steps
    case weight
}

private struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let style: MetricChartStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.fitnexTitle(size: 15))
                    .foregroundColor(FitnexColor.black)
                Spacer()
                SmallCircleIcon(systemName: icon)
            }

            Text(value)
                .font(.fitnexTitle(size: 15))
                .foregroundColor(FitnexColor.black)
                .padding(.top, 14)

            if let subtitle {
                Text(subtitle)
                    .font(.fitnexBody(size: 9, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                    .padding(.top, 2)
            }

            Spacer()

            switch style {
            case .miniBars:
                MiniBars()
                    .frame(height: 46)
            case .steps:
                StepsBars()
                    .frame(height: 50)
            case .weight:
                WeightSparkline()
                    .frame(height: 48)
            }
        }
        .padding(15)
        .frame(width: 155, height: 147)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private struct HeartCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Heart Rate")
                    .font(.fitnexTitle(size: 15))
                    .foregroundColor(FitnexColor.black)
                Spacer()
                SmallCircleIcon(systemName: "heart.fill")
            }

            Text("109 bpm")
                .font(.fitnexTitle(size: 15))
                .foregroundColor(FitnexColor.black)
                .padding(.top, 16)

            Text("15 minutes ago")
                .font(.fitnexBody(size: 9, weight: .regular))
                .foregroundColor(FitnexColor.grayText)
                .padding(.top, 2)

            Spacer()

            HeartBars()
                .frame(height: 68)
        }
        .padding(15)
        .frame(width: 155, height: 200)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private struct InviteCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(FitnexColor.orangeSoft)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(FitnexColor.orange)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Got 10% discount")
                    .font(.fitnexBody(size: 11, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                Text("Invite a friends!")
                    .font(.fitnexTitle(size: 15))
                    .foregroundColor(FitnexColor.black)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(FitnexColor.orange)
        }
        .padding(.horizontal, 15)
        .frame(width: 325, height: 70)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private enum FitnexTab {
    case home
    case location
    case activity
    case discovery
    case profile
}

private struct FitnexTabBar: View {
    let selected: FitnexTab
    let openActivity: () -> Void
    let feedback: (String) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white)
                .frame(height: 76)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FitnexColor.border)
                        .frame(height: 1)
                }

            HStack(spacing: 0) {
                tab(.profile, "person", action: { feedback("Profile") })
                tab(.location, "location", action: { feedback("Location") })
                Button(action: openActivity) {
                    Circle()
                        .fill(FitnexColor.orange)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                }
                .frame(maxWidth: .infinity)
                tab(.discovery, "safari", action: { feedback("Discovery") })
                tab(.home, "house", action: { feedback("Home") })
            }
            .padding(.horizontal, 38)
        }
        .frame(height: 84)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tab(_ tab: FitnexTab, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(tab == selected ? FitnexColor.orange : FitnexColor.grayText)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }
}

private struct ActivityRingCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let progress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.fitnexTitle(size: 11))
                    .foregroundColor(FitnexColor.black)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FitnexColor.lightText)
            }
            .padding(.horizontal, 15)
            .padding(.top, 22)

            Spacer()

            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.92)
                    .stroke(FitnexColor.pale, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(110))
                Circle()
                    .trim(from: 0.08, to: 0.08 + 0.84 * progress)
                    .stroke(FitnexColor.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(110))
                Circle()
                    .stroke(FitnexColor.pale, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 7]))
                    .frame(width: 68, height: 68)

                VStack(spacing: 1) {
                    Text(value)
                        .font(.fitnexTitle(size: 16))
                        .foregroundColor(FitnexColor.black)
                    Text(unit)
                        .font(.fitnexBody(size: 9, weight: .regular))
                        .foregroundColor(FitnexColor.grayText)
                }
            }
            .frame(width: 118, height: 118)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 23)
        }
        .frame(width: 155, height: 180)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private struct ProgressChart: View {
    private let points: [CGFloat] = [42, 38, 56, 85, 66, 98, 103, 70, 74, 86, 52, 61]
    private let labels = ["00:00", "06:00", "12:00", "18:00", "24:00"]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let left: CGFloat = 22
                    let right: CGFloat = 0
                    let top: CGFloat = 6
                    let bottom: CGFloat = 25
                    let chart = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)

                    for row in 0...5 {
                        let y = chart.minY + chart.height * CGFloat(row) / 5
                        var grid = Path()
                        grid.move(to: CGPoint(x: chart.minX, y: y))
                        grid.addLine(to: CGPoint(x: chart.maxX, y: y))
                        context.stroke(grid, with: .color(FitnexColor.pale), lineWidth: 1)
                    }

                    func point(_ index: Int, _ value: CGFloat) -> CGPoint {
                        let x = chart.minX + chart.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = chart.maxY - chart.height * value / 125
                        return CGPoint(x: x, y: y)
                    }

                    var line = Path()
                    line.move(to: point(0, points[0]))
                    for index in points.indices.dropFirst() {
                        line.addLine(to: point(index, points[index]))
                    }

                    var area = line
                    area.addLine(to: CGPoint(x: chart.maxX, y: chart.maxY))
                    area.addLine(to: CGPoint(x: chart.minX, y: chart.maxY))
                    area.closeSubpath()

                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [FitnexColor.orange.opacity(0.28), FitnexColor.orange.opacity(0.02)]),
                        startPoint: CGPoint(x: chart.midX, y: chart.minY),
                        endPoint: CGPoint(x: chart.midX, y: chart.maxY)
                    ))
                    context.stroke(line, with: .color(FitnexColor.orange), lineWidth: 1.2)

                    let markerX = point(6, points[6]).x
                    var marker = Path()
                    marker.move(to: CGPoint(x: markerX, y: chart.minY))
                    marker.addLine(to: CGPoint(x: markerX, y: chart.maxY))
                    context.stroke(marker, with: .color(FitnexColor.orange.opacity(0.85)), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: markerX - 3.5, y: point(6, points[6]).y - 3.5, width: 7, height: 7)), with: .color(.white))
                    context.stroke(Path(ellipseIn: CGRect(x: markerX - 3.5, y: point(6, points[6]).y - 3.5, width: 7, height: 7)), with: .color(FitnexColor.orange), lineWidth: 1.2)
                }

                VStack {
                    ForEach(["125", "100", "75", "50", "25", "0"], id: \.self) { label in
                        Text(label)
                            .font(.fitnexBody(size: 8, weight: .regular))
                            .foregroundColor(FitnexColor.grayText)
                            .frame(width: 16, alignment: .trailing)
                        if label != "0" { Spacer() }
                    }
                }
                .frame(height: 160)
                .padding(.top, 2)
            }

            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.fitnexBody(size: 8, weight: .regular))
                        .foregroundColor(FitnexColor.grayText)
                    if label != "24:00" { Spacer() }
                }
            }
            .padding(.leading, 42)
            .padding(.trailing, 4)
        }
    }
}

private struct WorkoutRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FitnexColor.orangeSoft)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(FitnexColor.orange)
            }
            .frame(width: 64, height: 58)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.fitnexTitle(size: 13))
                    .foregroundColor(FitnexColor.black)
                Text(detail)
                    .font(.fitnexBody(size: 9, weight: .regular))
                    .foregroundColor(FitnexColor.lightText)
                ProgressView(value: 0.62)
                    .tint(FitnexColor.orange)
                    .frame(width: 180)
            }

            Spacer()

            Circle()
                .fill(FitnexColor.orangeSoft)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FitnexColor.orange)
                }
        }
        .padding(.horizontal, 15)
        .frame(height: 80)
        .background(FitnexColor.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(FitnexColor.border, lineWidth: 1)
        }
    }
}

private struct SquareIconButton: View {
    let systemName: String
    let action: () -> Void
    var dot = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FitnexColor.lightText, lineWidth: 1)
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(FitnexColor.grayText)
                if dot {
                    Circle()
                        .fill(FitnexColor.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: -10, y: 10)
                }
            }
            .frame(width: 35, height: 35)
        }
    }
}

private struct SmallCircleIcon: View {
    let systemName: String

    var body: some View {
        Circle()
            .fill(FitnexColor.orangeSoft)
            .frame(width: 25, height: 25)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FitnexColor.orange)
            }
    }
}

private struct ProfileAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(FitnexColor.orangeSoft)
            Circle()
                .fill(Color(hex: 0xF4C7A1))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(y: -size * 0.18)
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(FitnexColor.orange)
                .frame(width: size * 0.56, height: size * 0.3)
                .offset(y: size * 0.16)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct MiniBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach([18, 38, 28, 48, 32], id: \.self) { height in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(height > 34 ? FitnexColor.orange : FitnexColor.orangeSoft)
                    .frame(width: 15, height: CGFloat(height))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct StepsBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach([22, 42, 28, 50, 36, 44, 31], id: \.self) { height in
                Capsule()
                    .fill(height > 40 ? FitnexColor.orange : FitnexColor.orangeSoft)
                    .frame(width: 10, height: CGFloat(height))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HeartBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach([64, 48, 30, 54, 38, 68], id: \.self) { height in
                Capsule()
                    .fill(height > 50 ? FitnexColor.orange : FitnexColor.orangeSoft)
                    .frame(width: 10, height: CGFloat(height))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct WeightSparkline: View {
    var body: some View {
        Canvas { context, size in
            let values: [CGFloat] = [38, 44, 32, 50, 43, 56, 49]
            let maxValue: CGFloat = 60
            func p(_ i: Int) -> CGPoint {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height - size.height * values[i] / maxValue
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.move(to: p(0))
            for i in values.indices.dropFirst() {
                path.addLine(to: p(i))
            }
            context.stroke(path, with: .color(FitnexColor.orange), lineWidth: 2)
        }
    }
}

private extension Font {
    static func fitnexTitle(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func fitnexBody(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}
