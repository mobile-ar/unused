//
//  Created by Fernando Romiti on 09/10/2024.
//

extension String {

    var rosewater: String { return "\u{001B}[38;2;245;224;220m\(self)\u{001B}[0m" }
    var flamingo: String { return "\u{001B}[38;2;242;205;205m\(self)\u{001B}[0m" }
    var pink: String { return "\u{001B}[38;2;245;194;231m\(self)\u{001B}[0m" }
    var mauve: String { return "\u{001B}[38;2;203;166;247m\(self)\u{001B}[0m" }
    var red: String { return "\u{001B}[38;2;243;139;168m\(self)\u{001B}[0m" }
    var maroon: String { return "\u{001B}[38;2;235;160;172m\(self)\u{001B}[0m" }
    var peach: String { return "\u{001B}[38;2;250;179;135m\(self)\u{001B}[0m" }
    var yellow: String { return "\u{001B}[38;2;249;226;175m\(self)\u{001B}[0m" }
    var green: String { return "\u{001B}[38;2;166;227;161m\(self)\u{001B}[0m" }
    var teal: String { return "\u{001B}[38;2;148;226;213m\(self)\u{001B}[0m" }
    var sky: String { return "\u{001B}[38;2;137;220;235m\(self)\u{001B}[0m" }
    var sapphire: String { return "\u{001B}[38;2;116;199;236m\(self)\u{001B}[0m" }
    var blue: String { return "\u{001B}[38;2;137;180;250m\(self)\u{001B}[0m" }
    var lavender: String { return "\u{001B}[38;2;180;190;254m\(self)\u{001B}[0m" }

    var text: String { return "\u{001B}[38;2;205;214;244m\(self)\u{001B}[0m" }
    var subtext1: String { return "\u{001B}[38;2;186;194;222m\(self)\u{001B}[0m" }
    var subtext0: String { return "\u{001B}[38;2;166;173;200m\(self)\u{001B}[0m" }
    var overlay2: String { return "\u{001B}[38;2;147;153;178m\(self)\u{001B}[0m" }
    var overlay1: String { return "\u{001B}[38;2;127;132;156m\(self)\u{001B}[0m" }
    var overlay0: String { return "\u{001B}[38;2;108;112;134m\(self)\u{001B}[0m" }
    var surface2: String { return "\u{001B}[38;2;88;91;112m\(self)\u{001B}[0m" }
    var surface1: String { return "\u{001B}[38;2;69;71;90m\(self)\u{001B}[0m" }
    var surface0: String { return "\u{001B}[38;2;49;50;68m\(self)\u{001B}[0m" }
    var base: String { return "\u{001B}[38;2;30;30;46m\(self)\u{001B}[0m" }
    var mantle: String { return "\u{001B}[38;2;24;24;37m\(self)\u{001B}[0m" }
    var crust: String { return "\u{001B}[38;2;17;17;27m\(self)\u{001B}[0m" }

    // Text styles
    var bold: String { return "\u{001B}[1m\(self)\u{001B}[22m" }
    var italic: String { return "\u{001B}[3m\(self)\u{001B}[23m" }
    var underline: String { return "\u{001B}[4m\(self)\u{001B}[24m" }

}
