//
//  String+Colors.swift
//  unused
//
//  Created by Fernando Romiti on 09/10/2024.
//

extension String {
    var black: String { return "\u{001B}[30m\(self)\u{001B}[0m" }
    var red: String { return "\u{001B}[31m\(self)\u{001B}[0m" }
    var green: String { return "\u{001B}[32m\(self)\u{001B}[0m" }
    var yellow: String { return "\u{001B}[33m\(self)\u{001B}[0m" }
    var blue: String { return "\u{001B}[34m\(self)\u{001B}[0m" }
    var magenta: String { return "\u{001B}[35m\(self)\u{001B}[0m" }
    var cyan: String { return "\u{001B}[36m\(self)\u{001B}[0m" }
    var gray: String { return "\u{001B}[37m\(self)\u{001B}[0m" }

    var bgBlack: String { return "\u{001B}[40m\(self)\u{001B}[0m" }
    var bgRed: String { return "\u{001B}[41m\(self)\u{001B}[0m" }
    var bgGreen: String { return "\u{001B}[42m\(self)\u{001B}[0m" }
    var bgBrown: String { return "\u{001B}[43m\(self)\u{001B}[0m" }
    var bgBlue: String { return "\u{001B}[44m\(self)\u{001B}[0m" }
    var bgMagenta: String { return "\u{001B}[45m\(self)\u{001B}[0m" }
    var bgCyan: String { return "\u{001B}[46m\(self)\u{001B}[0m" }
    var bgGray: String { return "\u{001B}[47m\(self)\u{001B}[0m" }

    var bold: String { return "\u{001B}[1m\(self)\u{001B}[22m" }
    var italic: String { return "\u{001B}[3m\(self)\u{001B}[23m" }
    var underline: String { return "\u{001B}[4m\(self)\u{001B}[24m" }
    var blink: String { return "\u{001B}[5m\(self)\u{001B}[25m" }
    var reverseColor: String { return "\u{001B}[7m\(self)\u{001B}[27m" }
}
