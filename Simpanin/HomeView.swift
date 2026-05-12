import Foundation
import SwiftUI

struct HomeView: View {
    @State private var selectedTab: FitnexTab = .home
    @State private var isActivityPresented = false
    @State private var feedbackMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            FitnexColor.background.ignoresSafeArea()

            currentScreen

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
        .safeAreaInset(edge: .bottom) {
            FitnexTabBar(
                selected: selectedTab,
                isActivityPresented: isActivityPresented,
                selectTab: selectTab,
                openActivity: openActivity
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
        .animation(.easeInOut(duration: 0.22), value: isActivityPresented)
        .animation(.easeInOut(duration: 0.18), value: feedbackMessage)
    }

    @ViewBuilder
    private var currentScreen: some View {
        if isActivityPresented {
            ActivityStatusView(
                back: { isActivityPresented = false },
                feedback: feedback
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            switch selectedTab {
            case .home:
                MinePageView(feedback: feedback)
            case .explore:
                PlaceholderScreen(
                    title: "Explore",
                    subtitle: "Quick access and discovery tools live here.",
                    icon: "safari"
                )
            case .location:
                PlaceholderScreen(
                    title: "Location",
                    subtitle: "Host nodes and network points can surface here.",
                    icon: "location"
                )
            case .profile:
                PlaceholderScreen(
                    title: "Profile",
                    subtitle: "Account, device and host preferences can live here.",
                    icon: "person"
                )
            }
        }
    }

    private func feedback(_ message: String) {
        feedbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if feedbackMessage == message {
                feedbackMessage = nil
            }
        }
    }

    private func selectTab(_ tab: FitnexTab) {
        selectedTab = tab
        isActivityPresented = false
    }

    private func openActivity() {
        isActivityPresented = true
    }
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
    let feedback: (String) -> Void

    @StateObject private var metrics = HomeMetricsViewModel()
    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                mineHeader

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metrics.snapshotDateText)
                                .font(.fitnexBody(size: 11, weight: .regular))
                                .foregroundColor(FitnexColor.grayText)
                            Text(metrics.snapshotTitleText)
                                .font(.fitnexTitle(size: 15))
                                .foregroundColor(FitnexColor.black)
                        }
                        Spacer()
                        Button {
                            feedback("Source: \(HomeMetricsViewModel.endpointHost)")
                        } label: {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(90))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(FitnexColor.black)
                                .frame(width: 32, height: 32)
                        }
                    }

                    MetricsStatusStrip(status: metrics.statusText, isLive: metrics.response != nil)
                }

                ChallengeCard(content: metrics.hostCard)

                LazyVGrid(columns: [
                    GridItem(.fixed(155), spacing: 15),
                    GridItem(.fixed(155), spacing: 15)
                ], alignment: .leading, spacing: 15) {
                    MetricCard(content: metrics.cpuCard)
                    MetricCard(content: metrics.memoryCard)
                    MetricCard(content: metrics.networkCard)
                    MetricCard(content: metrics.processCard)
                }

                SourceCard(
                    endpoint: HomeMetricsViewModel.endpointHost,
                    detail: metrics.sourceDetailText
                )
                .onTapGesture { feedback("GET /api/public/system/metrics") }

                Spacer(minLength: 136)
            }
            .padding(.horizontal, 25)
            .padding(.top, 44)
        }
        .task {
            await metrics.loadIfNeeded()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await metrics.refresh()
            }
        }
        .onChange(of: metrics.toastMessage) { message in
            guard let message else { return }
            feedback(message)
            metrics.toastMessage = nil
        }
    }

    private var mineHeader: some View {
        HStack(spacing: 12) {
            ProfileAvatar(size: 50)

            Text("Host monitor\nReady for polling?")
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
                    ActivityRingCard(title: "Sleep", value: "8HR", unit: "20 sec", icon: "moon.fill", progress: 0.52)
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
                .padding(.bottom, 136)
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

private struct MetricsStatusStrip: View {
    let status: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(isLive ? FitnexColor.orange : FitnexColor.border)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.fitnexBody(size: 11, weight: .regular))
                .foregroundColor(FitnexColor.grayText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChallengeCard: View {
    let content: HostCardContent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(FitnexColor.orangeSoft)
                Image(systemName: content.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(FitnexColor.orange)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.fitnexBody(size: 10, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                Text(content.primaryText)
                    .font(.fitnexTitle(size: 16))
                    .foregroundColor(FitnexColor.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(content.secondaryText)
                    .font(.fitnexBody(size: 10, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(content.trailingLabel)
                    .font(.fitnexBody(size: 10, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                Text(content.trailingValue)
                    .font(.fitnexTitle(size: 13))
                    .foregroundColor(FitnexColor.orange)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
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
    case process
}

private struct MetricCard: View {
    let content: MetricCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(content.title)
                    .font(.fitnexTitle(size: 15))
                    .foregroundColor(FitnexColor.black)
                Spacer()
                SmallCircleIcon(systemName: content.icon)
            }

            Text(content.value)
                .font(.fitnexTitle(size: 15))
                .foregroundColor(FitnexColor.black)
                .padding(.top, 14)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.fitnexBody(size: 9, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                    .padding(.top, 2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            switch content.style {
            case .miniBars:
                MiniBars()
                    .frame(height: 46)
            case .steps:
                StepsBars()
                    .frame(height: 50)
            case .weight:
                WeightSparkline()
                    .frame(height: 48)
            case .process:
                HeartBars()
                    .frame(height: 54)
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

private struct SourceCard: View {
    let endpoint: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(FitnexColor.orangeSoft)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(FitnexColor.orange)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(detail)
                    .font(.fitnexBody(size: 11, weight: .regular))
                    .foregroundColor(FitnexColor.grayText)
                Text(endpoint)
                    .font(.fitnexTitle(size: 15))
                    .foregroundColor(FitnexColor.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
    case explore
    case location
    case profile
}

private struct FitnexTabBar: View {
    let selected: FitnexTab
    let isActivityPresented: Bool
    let selectTab: (FitnexTab) -> Void
    let openActivity: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)
                .frame(height: 68)
                .shadow(color: Color.black.opacity(0.08), radius: 22, y: 8)

            HStack(spacing: 0) {
                tab(.home, "house")
                tab(.explore, "safari")
                Spacer(minLength: 62)
                tab(.location, "location")
                tab(.profile, "person")
            }
            .padding(.horizontal, 18)

            Button(action: openActivity) {
                ZStack {
                    Circle()
                        .fill(FitnexColor.orange)
                        .frame(width: 58, height: 58)
                        .shadow(color: FitnexColor.orange.opacity(0.35), radius: 16, y: 8)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -18)
            .scaleEffect(isActivityPresented ? 1.06 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: isActivityPresented)
        }
        .frame(height: 86)
    }

    private func tab(_ tab: FitnexTab, _ icon: String) -> some View {
        let isSelected = selected == tab && !isActivityPresented
        return Button(action: { selectTab(tab) }) {
            ZStack {
                Circle()
                    .fill(FitnexColor.orangeSoft.opacity(isSelected ? 1 : 0))
                    .frame(width: 34, height: 34)
                    .scaleEffect(isSelected ? 1 : 0.62)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? FitnexColor.orange : FitnexColor.grayText)
                    .scaleEffect(isSelected ? 1.12 : 1)
                    .offset(y: isSelected ? -2 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.66), value: isSelected)
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.fitnexTitle(size: 28))
                            .foregroundColor(FitnexColor.black)
                        Text(subtitle)
                            .font(.fitnexBody(size: 13, weight: .regular))
                            .foregroundColor(FitnexColor.grayText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                    Circle()
                        .fill(FitnexColor.orangeSoft)
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(FitnexColor.orange)
                        }
                }

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(FitnexColor.card)
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 14) {
                            Image(systemName: icon)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundColor(FitnexColor.orange)
                            Text("Placeholder")
                                .font(.fitnexTitle(size: 18))
                                .foregroundColor(FitnexColor.black)
                            Text("This tab is wired into the new bottom navigation and ready for a real screen.")
                                .font(.fitnexBody(size: 12, weight: .regular))
                                .foregroundColor(FitnexColor.grayText)
                                .multilineTextAlignment(.center)
                                .frame(width: 220)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(FitnexColor.border, lineWidth: 1)
                    }

                Spacer(minLength: 170)
            }
            .padding(.horizontal, 25)
            .padding(.top, 48)
        }
        .background(FitnexColor.background)
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

                    for row in 0 ... 5 {
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

            func point(_ index: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height - size.height * values[index] / maxValue
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: point(0))
            for index in values.indices.dropFirst() {
                path.addLine(to: point(index))
            }
            context.stroke(path, with: .color(FitnexColor.orange), lineWidth: 2)
        }
    }
}

private struct HostCardContent {
    let title: String
    let primaryText: String
    let secondaryText: String
    let trailingLabel: String
    let trailingValue: String
    let icon: String
}

private struct MetricCardContent {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let style: MetricChartStyle
}

@MainActor
private final class HomeMetricsViewModel: ObservableObject {
    static let endpointHost = "192.168.2.202:12225"
    private static let endpointURL = URL(string: "http://192.168.2.202:12225/api/public/system/metrics")!

    @Published private(set) var response: SystemMetricsResponse?
    @Published private(set) var isLoading = false
    @Published var toastMessage: String?

    private var didShowRefreshError = false

    var snapshotDateText: String {
        guard let response, let date = parseTimestamp(response.timestamp) else {
            return Self.dateFormatter.string(from: Date())
        }
        return Self.dateFormatter.string(from: date)
    }

    var snapshotTitleText: String {
        response == nil ? "Connecting to host" : "System Metrics Overview"
    }

    var statusText: String {
        if isLoading && response == nil {
            return "Loading metrics from \(Self.endpointHost)"
        }
        if let response, let date = parseTimestamp(response.timestamp) {
            return "Updated \(Self.timeFormatter.string(from: date))"
        }
        return "Waiting for reachable host"
    }

    var sourceDetailText: String {
        if let response, let date = parseTimestamp(response.timestamp) {
            return "Public metrics feed | \(Self.timeFormatter.string(from: date))"
        }
        return isLoading ? "Public metrics feed | loading" : "Public metrics feed | unavailable"
    }

    var hostCard: HostCardContent {
        guard let host = response?.host else {
            return HostCardContent(
                title: "Host",
                primaryText: isLoading ? "Connecting..." : "Host unavailable",
                secondaryText: isLoading ? "Reading public system metrics" : "Check the DownGo host and local network",
                trailingLabel: "Endpoint",
                trailingValue: "HTTP",
                icon: "desktopcomputer"
            )
        }

        return HostCardContent(
            title: "Host",
            primaryText: host.hostname,
            secondaryText: "\(host.platform) | \(host.os)",
            trailingLabel: "Uptime",
            trailingValue: formatDuration(host.uptimeSeconds),
            icon: "desktopcomputer"
        )
    }

    var cpuCard: MetricCardContent {
        guard let cpu = response?.cpu else {
            return placeholderCard(title: "CPU", icon: "cpu", style: .miniBars)
        }
        return MetricCardContent(
            title: "CPU",
            value: percent(cpu.usagePercent),
            subtitle: "\(cpu.logicalCores)L / \(cpu.physicalCores)P cores",
            icon: "cpu",
            style: .miniBars
        )
    }

    var memoryCard: MetricCardContent {
        guard let memory = response?.memory else {
            return placeholderCard(title: "Memory", icon: "memorychip", style: .weight)
        }
        return MetricCardContent(
            title: "Memory",
            value: "\(bytes(memory.usedBytes)) / \(bytes(memory.totalBytes))",
            subtitle: "\(percent(memory.usedPercent)) used",
            icon: "memorychip",
            style: .weight
        )
    }

    var networkCard: MetricCardContent {
        guard let interfaces = response?.network.interfaces else {
            return placeholderCard(title: "Network", icon: "arrow.left.arrow.right", style: .steps)
        }

        let totalRecv = interfaces.reduce(Int64(0)) { $0 + $1.bytesRecv }
        let totalSent = interfaces.reduce(Int64(0)) { $0 + $1.bytesSent }
        let activeInterfaces = interfaces.filter { $0.bytesRecv > 0 || $0.bytesSent > 0 }.count

        return MetricCardContent(
            title: "Network",
            value: bytes(totalRecv + totalSent),
            subtitle: "\(activeInterfaces) active | Tx \(bytes(totalSent))",
            icon: "arrow.left.arrow.right",
            style: .steps
        )
    }

    var processCard: MetricCardContent {
        guard let process = response?.process else {
            return placeholderCard(title: "Process", icon: "terminal", style: .process)
        }
        return MetricCardContent(
            title: "Process",
            value: formatDuration(process.uptimeSeconds),
            subtitle: "PID \(process.pid) | \(process.goroutines) goroutines",
            icon: "terminal",
            style: .process
        )
    }

    func loadIfNeeded() async {
        guard response == nil, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: Self.endpointURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, urlResponse) = try await URLSession.shared.data(for: request)

            if let httpResponse = urlResponse as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }

            response = try JSONDecoder().decode(SystemMetricsResponse.self, from: data)
            didShowRefreshError = false
        } catch {
            if response == nil {
                toastMessage = "Metrics host unavailable"
            } else if !didShowRefreshError {
                toastMessage = "Metrics refresh failed"
            }
            didShowRefreshError = true
        }
    }

    private func placeholderCard(title: String, icon: String, style: MetricChartStyle) -> MetricCardContent {
        MetricCardContent(
            title: title,
            value: isLoading ? "Loading..." : "Unavailable",
            subtitle: isLoading ? "Waiting for host" : "No fresh metrics",
            icon: icon,
            style: style
        )
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func percent(_ value: Int) -> String {
        "\(value)%"
    }

    private func bytes(_ value: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: value)
    }

    private func formatDuration(_ seconds: Int) -> String {
        guard let formatted = Self.durationFormatter.string(from: TimeInterval(seconds)) else {
            return "\(seconds)s"
        }
        return formatted
    }

    private func parseTimestamp(_ value: String) -> Date? {
        Self.fractionalFormatter.date(from: value) ?? Self.basicFormatter.date(from: value)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

private struct SystemMetricsResponse: Decodable {
    let timestamp: String
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let network: NetworkMetrics
    let host: HostMetrics
    let process: ProcessMetrics

    struct CPUMetrics: Decodable {
        let usagePercent: Double
        let logicalCores: Int
        let physicalCores: Int
        let modelName: String
    }

    struct MemoryMetrics: Decodable {
        let totalBytes: Int64
        let usedBytes: Int64
        let availableBytes: Int64
        let usedPercent: Int
    }

    struct NetworkMetrics: Decodable {
        let interfaces: [NetworkInterface]
    }

    struct NetworkInterface: Decodable {
        let name: String
        let bytesSent: Int64
        let bytesRecv: Int64
        let packetsSent: Int64
        let packetsRecv: Int64
    }

    struct HostMetrics: Decodable {
        let hostname: String
        let os: String
        let platform: String
        let uptimeSeconds: Int
    }

    struct ProcessMetrics: Decodable {
        let pid: Int
        let uptimeSeconds: Int
        let goroutines: Int
        let allocBytes: Int64
        let sysBytes: Int64
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
