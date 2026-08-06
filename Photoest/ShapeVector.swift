import CoreGraphics
import SwiftUI

struct ShapeVector {
    let viewBox: CGRect
    let pathData: String

    var aspectRatio: CGFloat {
        guard viewBox.height > 0 else { return 1 }
        return viewBox.width / viewBox.height
    }

    func path(in rect: CGRect) -> Path {
        Path(cgPath(in: rect))
    }

    func cgPath(in rect: CGRect) -> CGPath {
        let path = SVGPathParser(data: pathData).makePath()
        let sourceBounds = path.boundingBoxOfPath.isEmpty ? viewBox : path.boundingBoxOfPath
        let scale = min(rect.width / sourceBounds.width, rect.height / sourceBounds.height)
        let fittedWidth = sourceBounds.width * scale
        let fittedHeight = sourceBounds.height * scale
        let fittedOriginX = rect.minX + (rect.width - fittedWidth) / 2
        let fittedOriginY = rect.minY + (rect.height - fittedHeight) / 2
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: fittedOriginX - sourceBounds.minX * scale,
            ty: fittedOriginY - sourceBounds.minY * scale
        )

        return path.copy(using: &transform) ?? path
    }
}

extension SelectiveShape {
    var vector: ShapeVector {
        switch self {
        case .shape1:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 38, height: 46), pathData: "M0 0H37.1252V45.6331H0Z")
        case .shape2:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 53, height: 46), pathData: "M27.0718 8.31346C28.3574 6.71726 29.7209 5.27679 31.1624 3.99205C32.409 2.94089 33.8212 1.98707 35.399 1.13057C36.9768 0.274079 38.6228 -0.0957718 40.3369 0.0210231C42.7523 0.215681 44.7684 0.789922 46.3851 1.74375C48.0019 2.69757 49.2875 3.90445 50.242 5.36439C51.1964 6.82432 51.849 8.47892 52.1996 10.3282C52.5502 12.1774 52.6671 14.0753 52.5502 16.0219C52.4333 17.9685 52.0924 19.8275 51.5276 21.5989C50.9627 23.3703 50.2614 25.0249 49.4238 26.5627C48.5862 28.1005 47.661 29.5215 46.6481 30.8257C45.6352 32.1299 44.6223 33.3076 43.6094 34.3587C42.0511 35.9549 40.4246 37.444 38.7299 38.8261C37.0353 40.2082 35.4185 41.3956 33.8797 42.3884C32.3408 43.3811 30.9384 44.1695 29.6722 44.7534C28.4061 45.3374 27.4224 45.6294 26.7212 45.6294C25.942 45.6683 24.9486 45.3958 23.7409 44.8118C22.5332 44.2279 21.2086 43.4395 19.7672 42.4467C18.3258 41.454 16.8064 40.2763 15.2091 38.9137C13.6119 37.5511 12.0341 36.1106 10.4758 34.5923C9.46286 33.619 8.37204 32.49 7.2033 31.2052C6.03457 29.9205 4.93401 28.5092 3.90163 26.9714C2.86924 25.4336 1.98295 23.7693 1.24275 21.9785C0.502556 20.1876 0.0934988 18.2799 0.0155831 16.2555C-0.0623325 14.2311 0.151936 12.3331 0.658387 10.5618C1.16484 8.79037 1.92452 7.20391 2.93742 5.80237C3.95032 4.40083 5.19697 3.22315 6.67737 2.26932C8.15777 1.3155 9.83295 0.643929 11.7029 0.254613C12.6379 0.0599547 13.5729 0.0307563 14.5079 0.167017C15.4429 0.303278 16.3584 0.536867 17.2544 0.867786C18.1504 1.1987 19.0075 1.61722 19.8256 2.12333C20.6438 2.62944 21.4229 3.15502 22.1631 3.70006C23.8773 4.9848 25.5135 6.5226 27.0718 8.31346Z")
        case .shape3:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 65, height: 46), pathData: "M10.1077 20.8712C4.32557 21.4271 -0.0451761 26.8343 0.000352438 33.2521C0.045881 39.67 4.50768 44.9761 10.2898 45.4815V45.6331L52.9956 45.532C59.2786 44.774 64.1046 38.9625 64.1957 31.9382C64.1501 26.2784 60.9631 21.1744 56.1371 19.2036V18.1929C56.1371 8.13653 48.5794 0.000486334 39.2005 0.000486334C32.872 -0.0500481 27.0443 3.8411 24.085 10.0568C22.4459 8.33866 20.2606 7.42904 18.0297 7.42904C13.2947 7.37851 9.33371 11.5729 9.24266 16.879C9.24266 18.2939 9.56136 19.6584 10.1077 20.8712Z")
        case .shape4:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 46, height: 46), pathData: "M18.1538 2.35599C20.4687 -0.785331 25.1644 -0.78533 27.4793 2.35599L33.6612 10.7451C34.0062 11.2133 34.4198 11.6268 34.888 11.9718L43.2771 18.1538C46.4184 20.4687 46.4184 25.1644 43.2771 27.4793L34.888 33.6612C34.4198 34.0062 34.0062 34.4198 33.6612 34.888L27.4793 43.2771C25.1644 46.4184 20.4687 46.4184 18.1538 43.2771L11.9718 34.888C11.6268 34.4198 11.2133 34.0062 10.7451 33.6612L2.35599 27.4793C-0.785331 25.1644 -0.78533 20.4687 2.35599 18.1538L10.7451 11.9718C11.2133 11.6268 11.6268 11.2133 11.9718 10.7451L18.1538 2.35599Z")
        case .shape5:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 42, height: 47), pathData: "M19.5036 1.91951C20.2319 1.3602 21.2452 1.3602 21.9735 1.9195L29.4981 7.69804C29.6391 7.80628 29.7937 7.89553 29.9579 7.96348L38.7246 11.5907C39.5731 11.9418 40.0797 12.8193 39.9595 13.7297L38.7175 23.1355C38.6942 23.3117 38.6942 23.4902 38.7175 23.6664L39.9595 33.0722C40.0797 33.9825 39.5731 34.8601 38.7246 35.2111L29.9579 38.8384C29.7937 38.9063 29.6391 38.9956 29.4981 39.1038L21.9735 44.8824C21.2452 45.4417 20.2319 45.4417 19.5036 44.8824L11.979 39.1038C11.838 38.9956 11.6835 38.9063 11.5192 38.8384L2.75257 35.2111C1.90404 34.8601 1.39741 33.9825 1.51762 33.0722L2.75966 23.6664C2.78293 23.4902 2.78293 23.3117 2.75966 23.1355L1.51762 13.7297C1.39741 12.8193 1.90404 11.9418 2.75257 11.5907L11.5192 7.96348C11.6835 7.89553 11.838 7.80628 11.979 7.69804L19.5036 1.91951Z")
        case .shape6:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 45, height: 45), pathData: "M13.7498 6.35489C16.6105 -2.1183 28.2492 -2.11829 31.1098 6.35489L32.2794 9.81935L35.8411 9.89407C44.552 10.0768 48.1485 21.4734 41.2056 26.8929L38.3668 29.1088L39.3984 32.6194C41.9214 41.2056 32.5055 48.249 25.3539 43.1253L22.4298 41.0303L19.5057 43.1253C12.3541 48.249 2.93821 41.2056 5.46119 32.6194L6.49277 29.1088L3.654 26.8929C-3.28891 21.4734 0.307653 10.0768 9.01853 9.89407L12.5802 9.81935L13.7498 6.35489Z")
        case .shape7:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 48, height: 48), pathData: "M1.5 43.6562C1.5 45.1492 2.71037 46.3596 4.20344 46.3596H43.6562C45.1492 46.3596 46.3596 45.1492 46.3596 43.6562V23.9298C46.3596 11.5422 36.3174 1.5 23.9298 1.5C11.5422 1.5 1.5 11.5422 1.5 23.9298V43.6562Z")
        case .shape8:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 49, height: 49), pathData: "M39.2246 31.6797C43.3913 31.6799 46.7686 35.0579 46.7686 39.2246C46.7683 43.3912 43.3912 46.7683 39.2246 46.7686H9.04492C4.87822 46.7685 1.50021 43.3913 1.5 39.2246C1.5 35.0578 4.87809 31.6797 9.04492 31.6797H39.2246ZM39.2236 1.5C43.3905 1.5 46.7686 4.87804 46.7686 9.04492C46.7685 13.2116 43.3912 16.5896 39.2246 16.5898C43.3913 16.5901 46.7686 19.968 46.7686 24.1348C46.7683 28.3013 43.3912 31.6785 39.2246 31.6787H9.04492C4.87822 31.6787 1.50022 28.3014 1.5 24.1348C1.5 20.098 4.67057 16.8015 8.65723 16.5996L9.04492 16.5898C4.87809 16.5898 1.50007 13.2117 1.5 9.04492C1.5 4.87804 4.87804 1.5 9.04492 1.5H39.2236Z")
        case .shape9:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 45, height: 45), pathData: "M0 4.05516C0 1.81556 1.81556 0 4.05517 0H17.8252C32.7559 0 44.8596 12.1037 44.8596 27.0344V40.8045C44.8596 43.0441 43.0441 44.8596 40.8044 44.8596H27.0344C12.1037 44.8596 0 32.7559 0 17.8252V4.05516Z")
        case .shape10:
            ShapeVector(viewBox: CGRect(x: 0, y: 0, width: 49, height: 46), pathData: "M1.5 9.94826C1.5 5.28241 5.28241 1.5 9.94826 1.5H38.6848C43.3506 1.5 47.1331 5.28242 47.1331 9.94826V24.5684C47.1331 27.1837 45.9218 29.6515 43.853 31.2514L29.4847 42.3629C26.4412 44.7165 22.1918 44.7165 19.1483 42.3629L4.78005 31.2514C2.71122 29.6515 1.5 27.1837 1.5 24.5684L1.5 9.94826Z")
        }
    }
}

private struct SVGPathParser {
    private let scalars: [UnicodeScalar]
    private var index = 0
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var command: UnicodeScalar?

    init(data: String) {
        self.scalars = Array(data.unicodeScalars)
    }

    func makePath() -> CGPath {
        var parser = self
        return parser.parse()
    }

    private mutating func parse() -> CGPath {
        let path = CGMutablePath()

        while index < scalars.count {
            skipSeparators()
            if let next = peek(), next.properties.isAlphabetic {
                command = readScalar()
            }

            guard let command else { break }
            let relative = CharacterSet.lowercaseLetters.contains(command)

            switch Character(String(command).uppercased()) {
            case "M":
                guard let first = readPoint(relative: relative) else { break }
                path.move(to: first)
                current = first
                subpathStart = first

                while let point = readPoint(relative: relative) {
                    path.addLine(to: point)
                    current = point
                }
            case "L":
                while let point = readPoint(relative: relative) {
                    path.addLine(to: point)
                    current = point
                }
            case "H":
                while let number = readNumber() {
                    let x = relative ? current.x + number : number
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                }
            case "V":
                while let number = readNumber() {
                    let y = relative ? current.y + number : number
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                }
            case "C":
                while let c1 = readPoint(relative: relative),
                      let c2 = readPoint(relative: relative),
                      let end = readPoint(relative: relative) {
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                }
            case "Z":
                path.closeSubpath()
                current = subpathStart
            default:
                break
            }
        }

        return path
    }

    private mutating func readPoint(relative: Bool) -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        let point = CGPoint(x: x, y: y)
        return relative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
    }

    private mutating func readNumber() -> CGFloat? {
        skipSeparators()
        let start = index

        if peek() == "-" || peek() == "+" {
            index += 1
        }

        var hasDigits = false
        while let scalar = peek(), scalar.isDigit {
            hasDigits = true
            index += 1
        }

        if peek() == "." {
            index += 1
            while let scalar = peek(), scalar.isDigit {
                hasDigits = true
                index += 1
            }
        }

        if peek() == "e" || peek() == "E" {
            let exponentStart = index
            index += 1
            if peek() == "-" || peek() == "+" {
                index += 1
            }

            var hasExponentDigits = false
            while let scalar = peek(), scalar.isDigit {
                hasExponentDigits = true
                index += 1
            }

            if !hasExponentDigits {
                index = exponentStart
            }
        }

        guard hasDigits, start < index else {
            index = start
            return nil
        }

        return CGFloat(Double(String(String.UnicodeScalarView(scalars[start..<index]))) ?? 0)
    }

    private mutating func skipSeparators() {
        while let scalar = peek(), scalar == "," || scalar.properties.isWhitespace {
            index += 1
        }
    }

    private func peek() -> UnicodeScalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func readScalar() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        defer { index += 1 }
        return scalars[index]
    }
}

private extension UnicodeScalar {
    var isDigit: Bool {
        value >= 48 && value <= 57
    }
}
