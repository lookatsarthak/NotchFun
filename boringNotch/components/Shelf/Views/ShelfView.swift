//
//  ShelfItemView.swift
//  NotchFun
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @Environment(BoringViewModel.self) var vm
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @Default(.shelfNewestFirst) private var newestFirst
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            // Narrower than the square it was, which took a quarter of the shelf and left
            // room for about two files fewer.
            FileShareView()
                .frame(width: 92)
                .environment(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
        }
        .overlay(alignment: .bottom) {
            if let error = tvm.lastDropError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .animation(NotchMotion.content, value: tvm.lastDropError)
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    private var clearButton: some View {
        ClearConfirmButton(
            count: tvm.items.count,
            idleHelp: "Clear the shelf — your files are not deleted",
            confirmHelp: "Remove everything from the shelf",
            action: tvm.clearAll
        )
    }

    var panel: some View {
        // Dashed "drop here" only while something is being dragged; at rest, a quiet
        // panel. Dashes all the time said "drop here" to nobody.
        RoundedRectangle(cornerRadius: NotchRadius.panel, style: .continuous)
            .fill(Color.white.opacity(vm.anyDropZoneTargeting ? 0 : 0.04))
            .overlay {
                if vm.anyDropZoneTargeting {
                    RoundedRectangle(cornerRadius: NotchRadius.panel, style: .continuous)
                        .stroke(
                            vm.dragDetectorTargeting ? Color.effectiveAccent.opacity(0.9) : Color.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                }
            }
            .overlay {
                content
                    .padding()
            }
            .overlay(alignment: .topTrailing) {
                if !tvm.items.isEmpty {
                    clearButton
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(newestFirst ? Array(tvm.items.reversed()) : tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                // The last item fades out at the edge instead of being cut, which says
                // "there's more" when the row scrolls.
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                }
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
