import SwiftUI

struct LibraryBrowseControlsView: View {
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void

    init(
        viewModel: LibraryBrowseControlsViewModel,
        showsBackButton: Bool = false,
        onNavigateBack: @escaping () -> Void = {},
    ) {
        self.viewModel = viewModel
        self.showsBackButton = showsBackButton
        self.onNavigateBack = onNavigateBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let panel = viewModel.activePanel {
                optionsRow(for: panel)
            }
        }
        .sheet(item: $viewModel.activeFilterSheet) { sheet in
            LibraryBrowseFilterSheetView(viewModel: viewModel, filter: sheet.filter)
        }
    }

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pillSpacing) {
                if showsBackButton {
                    LibraryBrowsePillButton(
                        title: String(localized: "library.browse.folders.back"),
                        systemImage: "chevron.left",
                        isSelected: false,
                        showsDisclosure: false,
                        action: onNavigateBack,
                    )
                }
                LibraryBrowsePillButton(
                    title: viewModel.typePillTitle,
                    systemImage: "square.grid.2x2",
                    isSelected: viewModel.activePanel == .type,
                    showsDisclosure: true,
                ) {
                    viewModel.togglePanel(.type)
                }

                if viewModel.showsFilterPill {
                    LibraryBrowsePillButton(
                        title: viewModel.filterPillTitle,
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: viewModel.activePanel == .filters || !viewModel.selectedFilters.isEmpty,
                        showsDisclosure: true,
                    ) {
                        viewModel.togglePanel(.filters)
                    }
                }

                if viewModel.showsSortPill {
                    LibraryBrowsePillButton(
                        title: viewModel.sortPillTitle,
                        systemImage: "arrow.up.arrow.down.circle",
                        isSelected: viewModel.activePanel == .sort || viewModel.selectedSort != nil,
                        showsDisclosure: true,
                    ) {
                        viewModel.togglePanel(.sort)
                    }
                }
            }
            .padding(rowPadding)
        }
    }

    @ViewBuilder
    private func optionsRow(for panel: LibraryBrowseControlsViewModel.Panel) -> some View {
        switch panel {
        case .type:
            typeOptions
        case .filters:
            filterOptions
        case .sort:
            sortOptions
        }
    }

    private var typeOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pillSpacing) {
                ForEach(viewModel.displayTypes) { type in
                    LibraryBrowsePillButton(
                        title: type.title,
                        systemImage: nil,
                        isSelected: type.key == viewModel.selectedDisplayType?.key,
                        showsDisclosure: false,
                    ) {
                        viewModel.selectDisplayType(type)
                    }
                }
            }
            .padding(rowPadding)
        }
    }

    private var filterOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pillSpacing) {
                ForEach(viewModel.availableFilters, id: \.filter) { filter in
                    let selection = viewModel.filterSelection(for: filter)
                    let isSelected = selection?.isEnabled == true
                    let label = filterLabel(for: filter, selection: selection)

                    LibraryBrowsePillButton(
                        title: label,
                        systemImage: isSelected ? "checkmark" : nil,
                        isSelected: isSelected,
                        showsDisclosure: !filter.isBoolean,
                    ) {
                        viewModel.toggleFilter(filter)
                    }
                }
            }
            .padding(rowPadding)
        }
    }

    private var sortOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pillSpacing) {
                ForEach(viewModel.availableSorts, id: \.key) { sort in
                    let selection = viewModel.selectedSort
                    let isSelected = selection?.sort.key == sort.key
                    let systemImage = sortDirectionImage(for: selection, sort: sort)

                    LibraryBrowsePillButton(
                        title: sort.title,
                        systemImage: systemImage,
                        isSelected: isSelected,
                        showsDisclosure: false,
                    ) {
                        viewModel.toggleSort(sort)
                    }
                }
            }
            .padding(rowPadding)
        }
    }

    private func filterLabel(
        for filter: PlexSectionItemFilter,
        selection: LibraryBrowseControlsViewModel.FilterSelection?,
    ) -> String {
        guard let selection else { return filter.title }
        guard let option = selection.selectedOption else { return filter.title }
        return filter.title + ": " + option.title
    }

    private func sortDirectionImage(
        for selection: LibraryBrowseControlsViewModel.SortSelection?,
        sort: PlexSectionItemSort,
    ) -> String? {
        guard let selection, selection.sort.key == sort.key else { return nil }
        switch selection.direction {
        case .asc:
            return "arrow.up"
        case .desc:
            return "arrow.down"
        }
    }

    private var pillSpacing: CGFloat {
        #if os(tvOS)
            36
        #else
            8
        #endif
    }

    private var rowPadding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 20, leading: 36, bottom: 20, trailing: 36)
        #else
            EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        #endif
    }
}

private struct LibraryBrowsePillButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let showsDisclosure: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if showsDisclosure {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1.2)
            }
            .shadow(color: shadowColor, radius: isFocused ? 14 : 4)
            .scaleEffect(isFocused ? 1.05 : (isSelected ? 1.02 : 1.0))
            .foregroundStyle(foregroundColor)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .focusEffectDisabled()
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if isSelected { return .white }
        return isFocused ? .white : .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.brandPrimary.opacity(isFocused ? 0.72 : 0.56)
        }
        return Color.white.opacity(isFocused ? 0.12 : 0.07)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.brandPrimary.opacity(isFocused ? 1.0 : 0.82)
        }
        return isFocused ? Color.brandPrimary.opacity(0.88) : Color.white.opacity(0.22)
    }

    private var shadowColor: Color {
        (isFocused || isSelected) ? Color.brandPrimary.opacity(isFocused ? 0.58 : 0.28) : .clear
    }
}

private struct LibraryBrowseFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let filter: PlexSectionItemFilter

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(filter.title)
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if viewModel.filterSelection(for: filter) != nil {
                            Button("library.browse.filters.clear") {
                                viewModel.clearFilter(filter)
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("common.actions.done") {
                            dismiss()
                        }
                    }
                }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                contentBody
            }
            .padding(.top, 12)
        #else
            contentBody
        #endif
    }

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.isLoadingOptions(for: filter) {
            VStack(spacing: 12) {
                ProgressView()
                Text("library.browse.filters.loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.optionsError(for: filter) {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
        } else if viewModel.options(for: filter).isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease.circle",
            )
        } else {
            List {
                ForEach(viewModel.options(for: filter)) { option in
                    Button {
                        viewModel.selectFilterOption(option, for: filter)
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer()
                            if viewModel.filterSelection(for: filter)?.selectedOption?.id == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    #if os(tvOS)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    #endif
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 16)
            #endif
            .listStyle(.plain)
        }
    }

    private var headerRow: some View {
        HStack {
            if viewModel.filterSelection(for: filter) != nil {
                Button("library.browse.filters.clear") {
                    viewModel.clearFilter(filter)
                    dismiss()
                }
            }
            Spacer()
            Button("common.actions.done") {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
    }
}
