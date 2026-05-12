import SwiftUI

struct HomeView: View {
    @State private var selectedTab: Tab = .home
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isCreateSheetPresented = false
    @State private var feedbackMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            Group {
                if selectedTab == .home {
                    homeContent
                } else {
                    PlaceholderTabView(tab: selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomNavigation(
                selectedTab: $selectedTab,
                createAction: { isCreateSheetPresented = true }
            )
        }
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .foregroundStyle(SimpaninColor.text)
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateSheet(
                bookmarkAction: {
                    feedback("Bookmark creation selected")
                    isCreateSheetPresented = false
                },
                collectionAction: {
                    feedback("Collection creation selected")
                    isCreateSheetPresented = false
                }
            )
            .presentationDetents([.height(214)])
            .presentationDragIndicator(.hidden)
        }
        .overlay(alignment: .top) {
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SimpaninColor.text.opacity(0.9), in: Capsule())
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: feedbackMessage)
    }

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hello, John Doe!")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(SimpaninColor.text)
                    .padding(.top, 56)

                SearchBar(
                    text: $searchText,
                    isActive: $isSearchActive
                )
                .padding(.top, 31)

                HStack(spacing: 16) {
                    ShortcutCard(title: "Links", assetName: "ShortcutLinks", background: SimpaninColor.purpleSoft)
                    ShortcutCard(title: "Images", assetName: "ShortcutImages", background: SimpaninColor.blueSoft)
                    ShortcutCard(title: "Documents", assetName: "ShortcutDocuments", background: SimpaninColor.redSoft)
                }
                .padding(.top, 38)

                HStack {
                    Text("My Collections")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Spacer()
                    Button {
                        feedback("Collections list is not implemented yet")
                    } label: {
                        HStack(spacing: 7) {
                            Text("See All")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SimpaninColor.primary)
                    }
                }
                .padding(.top, 36)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        CollectionCard(title: "Inspiration", count: "32 items", badgeName: "Image11")
                        CollectionCard(title: "Catboosters", count: "163 items", badgeName: "Image12")
                        CollectionCard(title: "Brain Foods", count: "26 items", badgeName: "Image13")
                    }
                    .padding(.trailing, 24)
                }
                .padding(.top, 17)

                Text("Recent bookmark")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .padding(.top, 33)

                RecentBookmarkRow(moreAction: { feedback("Bookmark options are not implemented yet") })
                    .padding(.top, 17)

                Spacer(minLength: 96)
            }
            .padding(.horizontal, 24)
        }
    }

    private func feedback(_ message: String) {
        feedbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if feedbackMessage == message {
                feedbackMessage = nil
            }
        }
    }
}

private enum Tab: String, CaseIterable, Identifiable {
    case home = "Home"
    case bookmarks = "Bookmarks"
    case collections = "Collections"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .bookmarks: return "bookmark"
        case .collections: return "cube"
        case .settings: return "gearshape"
        }
    }
}

private enum SimpaninColor {
    static let primary = Color(hex: 0x5460FE)
    static let text = Color(hex: 0x051E56)
    static let text80 = Color(hex: 0x526286)
    static let text60 = Color(hex: 0x9CA5BA)
    static let text40 = Color(hex: 0xB3BCCF)
    static let background = Color(hex: 0xF5F8FD)
    static let line = Color(hex: 0xEEF2F9)
    static let yellowSoft = Color(hex: 0xFFF5DD)
    static let purpleSoft = Color(hex: 0xF5ECFF)
    static let blueSoft = Color(hex: 0xE0F3FF)
    static let redSoft = Color(hex: 0xFFEBEF)
}

private struct SearchBar: View {
    @Binding var text: String
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? SimpaninColor.primary : Color(hex: 0xAFC0DB))

            TextField("Search your bookmark", text: $text)
                .focused($isFocused)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(SimpaninColor.text)
                .tint(SimpaninColor.primary)
                .onTapGesture { isActive = true }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SimpaninColor.text40)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(SimpaninColor.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? SimpaninColor.primary.opacity(0.35) : .clear, lineWidth: 1)
        }
        .onChange(of: isFocused) { focused in
            isActive = focused
        }
    }
}

private struct ShortcutCard: View {
    let title: String
    let assetName: String
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 45, height: 45)
            }
            .frame(width: 98, height: 96)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SimpaninColor.text)
        }
        .frame(width: 98, alignment: .leading)
    }
}

private struct CollectionCard: View {
    let title: String
    let count: String
    let badgeName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SimpaninColor.yellowSoft)
                Image("CollectionFolder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                Image(badgeName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .offset(x: 27, y: 27)
            }
            .frame(width: 114, height: 112)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SimpaninColor.text)
                .lineLimit(1)
                .padding(.top, 10)

            Text(count)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(SimpaninColor.text60)
                .padding(.top, 4)
        }
        .frame(width: 114, alignment: .leading)
    }
}

private struct RecentBookmarkRow: View {
    let moreAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image("RecentThumb")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top UI/UX Design Works for Inspiration")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SimpaninColor.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("UI & UX Design Inspiration")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(SimpaninColor.text80)

                    HStack(spacing: 6) {
                        Image("Image11")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text("Inspiration")
                        Circle()
                            .frame(width: 3, height: 3)
                        Text("12:21")
                    }
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(SimpaninColor.text60)
                }

                Spacer(minLength: 4)

                Button(action: moreAction) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SimpaninColor.text)
                        .frame(width: 24, height: 24)
                }
            }

            Rectangle()
                .fill(SimpaninColor.line)
                .frame(height: 1)
        }
    }
}

private struct BottomNavigation: View {
    @Binding var selectedTab: Tab
    let createAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.home)
            tabButton(.bookmarks)

            Button(action: createAction) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(SimpaninColor.primary)
                    .frame(width: 36, height: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(SimpaninColor.primary, lineWidth: 1.5)
                    }
            }
            .frame(maxWidth: .infinity)

            tabButton(.collections)
            tabButton(.settings)
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
        .background(SimpaninColor.background)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .regular))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular, design: .rounded))
            }
            .foregroundStyle(selectedTab == tab ? SimpaninColor.primary : SimpaninColor.text60)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CreateSheet: View {
    let bookmarkAction: () -> Void
    let collectionAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Create new")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(SimpaninColor.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SimpaninColor.text)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.top, 28)

            SheetActionRow(
                title: "Bookmarks",
                icon: "bookmark",
                action: bookmarkAction
            )
            .padding(.top, 18)

            Divider()
                .background(SimpaninColor.line)
                .padding(.leading, 40)

            SheetActionRow(
                title: "Collections",
                icon: "cube",
                action: collectionAction
            )
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
    }
}

private struct SheetActionRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SimpaninColor.primary)
                    .frame(width: 28, height: 28)
                    .background(SimpaninColor.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(SimpaninColor.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SimpaninColor.text60)
            }
            .frame(height: 42)
        }
    }
}

private struct PlaceholderTabView: View {
    let tab: Tab

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: tab.icon)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(SimpaninColor.primary)
            Text(tab.rawValue)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(SimpaninColor.text)
            Text("This screen is reserved for the next prototype pass.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(SimpaninColor.text60)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 68)
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
