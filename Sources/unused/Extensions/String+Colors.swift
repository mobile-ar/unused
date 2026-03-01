//
//  Created by Fernando Romiti on 09/10/2024.
//

extension String {

    // Text colors
    var rosewater: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;245;224;220m\(self)\u{001B}[0m" : self }
    var flamingo: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;242;205;205m\(self)\u{001B}[0m" : self }
    var pink: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;245;194;231m\(self)\u{001B}[0m" : self }
    var mauve: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;203;166;247m\(self)\u{001B}[0m" : self }
    var red: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;243;139;168m\(self)\u{001B}[0m" : self }
    var maroon: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;235;160;172m\(self)\u{001B}[0m" : self }
    var peach: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;250;179;135m\(self)\u{001B}[0m" : self }
    var yellow: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;249;226;175m\(self)\u{001B}[0m" : self }
    var green: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;166;227;161m\(self)\u{001B}[0m" : self }
    var teal: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;148;226;213m\(self)\u{001B}[0m" : self }
    var sky: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;137;220;235m\(self)\u{001B}[0m" : self }
    var sapphire: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;116;199;236m\(self)\u{001B}[0m" : self }
    var blue: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;137;180;250m\(self)\u{001B}[0m" : self }
    var lavender: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;180;190;254m\(self)\u{001B}[0m" : self }

    var text: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;205;214;244m\(self)\u{001B}[0m" : self }
    var subtext1: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;186;194;222m\(self)\u{001B}[0m" : self }
    var subtext0: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;166;173;200m\(self)\u{001B}[0m" : self }
    var overlay2: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;147;153;178m\(self)\u{001B}[0m" : self }
    var overlay1: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;127;132;156m\(self)\u{001B}[0m" : self }
    var overlay0: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;108;112;134m\(self)\u{001B}[0m" : self }
    var surface2: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;88;91;112m\(self)\u{001B}[0m" : self }
    var surface1: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;69;71;90m\(self)\u{001B}[0m" : self }
    var surface0: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;49;50;68m\(self)\u{001B}[0m" : self }
    var base: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;30;30;46m\(self)\u{001B}[0m" : self }
    var mantle: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;24;24;37m\(self)\u{001B}[0m" : self }
    var crust: String { OutputConfig.colorEnabled ? "\u{001B}[38;2;17;17;27m\(self)\u{001B}[0m" : self }

    // Text styles
    var bold: String { OutputConfig.colorEnabled ? "\u{001B}[1m\(self)\u{001B}[22m" : self }
    var italic: String { OutputConfig.colorEnabled ? "\u{001B}[3m\(self)\u{001B}[23m" : self }
    var underline: String { OutputConfig.colorEnabled ? "\u{001B}[4m\(self)\u{001B}[24m" : self }

}