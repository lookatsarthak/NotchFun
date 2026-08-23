import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    ///
    /// Both are narrow upright symbols: they stand beside the numerals inside the glyph,
    /// where the landscape plug would cost more width than all three digits together.
    var iconStatus: String {
        if isCharging {
            return "bolt.fill"
        }
        else if isPluggedIn {
            return "powerplug.portrait.fill"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    /// The interior the fill sweeps across, and the box the readout has to live in.
    private var cavityWidth: CGFloat { batteryWidth - 6 }

    private var fillWidth: CGFloat {
        CGFloat(min(max(levelBattery, 0), 100) / 100) * cavityWidth
    }

    /// Proportional rather than the old `(batteryWidth - 2.75) - 18`, which lands on the
    /// same height at the 30pt the app draws but collapses below the digits' cap height at
    /// smaller widths — the numerals sit on this bar, so it has to stay taller than they are.
    private var fillHeight: CGFloat { batteryWidth * 0.31 }

    private var showsLevel: Bool { Defaults[.showBatteryPercentage] }

    private var showsStatus: Bool {
        iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons])
    }

    /// Condensed and rounded because three digits have to clear a cavity around 24pt wide,
    /// bold because the counters of 8 and 0 close up at this size against a lit fill.
    /// Monospaced digits so the readout does not re-centre itself on every percent.
    private var readoutFont: Font {
        .system(size: batteryWidth * 0.3, weight: .bold, design: .rounded)
            .width(.condensed)
            .monospacedDigit()
    }

    /// Smaller than the numerals so the two carry equal optical weight: a symbol set at the
    /// digits' point size stands as tall as their ascenders and takes over the cavity.
    private var symbolFont: Font {
        .system(size: batteryWidth * 0.23, weight: .bold)
    }

    /// The digits scale rather than truncate: a bolt beside "100" is the one combination
    /// that outgrows the cavity, and the symbol is the half that must stay unambiguous.
    private func readout(_ color: Color) -> some View {
        HStack(spacing: 0) {
            if showsStatus {
                Image(systemName: iconStatus)
                    .font(symbolFont)
            }
            if showsLevel {
                Text(verbatim: "\(Int(levelBattery.rounded()))")
                    .font(readoutFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(color)
        .frame(width: cavityWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(batteryColor)
                .frame(
                    width: fillWidth,
                    height: fillHeight
                )
                .padding(.leading, 2)

            if showsLevel || showsStatus {
                // Drawn twice because the cavity is two-toned: the white copy carries the
                // unfilled side, and the copy clipped to the fill flips to black, so the
                // readout survives the boundary passing through the middle of a digit.
                ZStack(alignment: .leading) {
                    readout(.white)
                    readout(.black)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: fillWidth)
                        }
                }
                .padding(.leading, 2)
            }
        }
        .animation(NotchMotion.content, value: levelBattery)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(NotchMotion.control, value: configuration.isPressed)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%")
                    .font(.subheadline)
                    .fontWeight(.regular)
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                    
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

/// A view that displays the battery status and allows interaction to show detailed information.
struct BoringBatteryView: View {
    
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Button(action: {
            withAnimation {
                showPopupMenu.toggle()
            }
        }) {
            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

#Preview {
    BoringBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false
    ).frame(width: 200, height: 200)
}

#Preview("Levels") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach([Float(5), 42, 68, 100], id: \.self) { level in
            HStack(spacing: 16) {
                BatteryView(
                    levelBattery: level,
                    isPluggedIn: false,
                    isCharging: false,
                    isInLowPowerMode: false,
                    batteryWidth: 30,
                    isForNotification: false
                )
                BatteryView(
                    levelBattery: level,
                    isPluggedIn: true,
                    isCharging: true,
                    isInLowPowerMode: false,
                    batteryWidth: 30,
                    isForNotification: true
                )
            }
        }
    }
    .padding(24)
    .background(.black)
}
