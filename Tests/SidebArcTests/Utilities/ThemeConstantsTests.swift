import Foundation
import Testing
@testable import SidebArcCore

@MainActor
@Suite struct ThemeConstantsTests {

    // MARK: - Color Tests

    @Test func testColorsAreValid() {
        // Valid sRGB components (0-1) and not fully transparent.
        for color in [ThemeConstants.Colors.darkGray, ThemeConstants.Colors.white, ThemeConstants.Colors.settingsBackground] {
            let rgb = color.usingColorSpace(.sRGB)
            #expect(rgb != nil)
            if let rgb {
                for component in [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent] {
                    #expect((0...1).contains(component))
                }
                #expect(rgb.alphaComponent > 0)
            }
        }
    }

    @Test func testDarkGrayColor() {
        let color = ThemeConstants.Colors.darkGray
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(abs(red - (0.078)) <= 0.001)
        #expect(abs(green - (0.078)) <= 0.001)
        #expect(abs(blue - (0.078)) <= 0.001)
        #expect(abs(alpha - (1.0)) <= 0.001)
    }

    // MARK: - Opacity Tests

    @Test func testOpacityValuesInValidRange() {
        // All opacity values should be between 0 and 1
        #expect(ThemeConstants.Opacity.full >= 0)
        #expect(ThemeConstants.Opacity.full <= 1)

        #expect(ThemeConstants.Opacity.high >= 0)
        #expect(ThemeConstants.Opacity.high <= 1)

        #expect(ThemeConstants.Opacity.medium >= 0)
        #expect(ThemeConstants.Opacity.medium <= 1)

        #expect(ThemeConstants.Opacity.low >= 0)
        #expect(ThemeConstants.Opacity.low <= 1)

        #expect(ThemeConstants.Opacity.subtle >= 0)
        #expect(ThemeConstants.Opacity.subtle <= 1)

        #expect(ThemeConstants.Opacity.extraSubtle >= 0)
        #expect(ThemeConstants.Opacity.extraSubtle <= 1)

        #expect(ThemeConstants.Opacity.minimal >= 0)
        #expect(ThemeConstants.Opacity.minimal <= 1)
    }

    @Test func testOpacityValuesOrdered() {
        // Verify opacity values are in descending order
        #expect(ThemeConstants.Opacity.full > ThemeConstants.Opacity.high)
        #expect(ThemeConstants.Opacity.high > ThemeConstants.Opacity.medium)
        #expect(ThemeConstants.Opacity.medium > ThemeConstants.Opacity.low)
        #expect(ThemeConstants.Opacity.low > ThemeConstants.Opacity.subtle)
        #expect(ThemeConstants.Opacity.subtle > ThemeConstants.Opacity.extraSubtle)
        #expect(ThemeConstants.Opacity.extraSubtle > ThemeConstants.Opacity.minimal)
    }

    // MARK: - Font Tests

    @Test func testFontsAreSystemAvailable() {
        #expect(ThemeConstants.Fonts.bodyRegular.pointSize == 14)
        #expect(ThemeConstants.Fonts.bodySemibold.pointSize == 14)
        #expect(ThemeConstants.Fonts.bodyMedium.pointSize == 14)
        #expect(ThemeConstants.Fonts.bodyBold.pointSize == 14)
    }

    @Test func testSystemFontFunction() {
        let customFont = ThemeConstants.Fonts.systemFont(size: 16, weight: .light)
        #expect(customFont.pointSize == 16)
    }

    // MARK: - Spacing Tests

    @Test func testSpacingValuesArePositive() {
        #expect(ThemeConstants.Spacing.tiny > 0)
        #expect(ThemeConstants.Spacing.small > 0)
        #expect(ThemeConstants.Spacing.medium > 0)
        #expect(ThemeConstants.Spacing.regular > 0)
        #expect(ThemeConstants.Spacing.large > 0)
        #expect(ThemeConstants.Spacing.extraLarge > 0)
        #expect(ThemeConstants.Spacing.huge > 0)
    }

    @Test func testSpacingValuesOrdered() {
        // Verify spacing values are in ascending order
        #expect(ThemeConstants.Spacing.tiny < ThemeConstants.Spacing.small)
        #expect(ThemeConstants.Spacing.small < ThemeConstants.Spacing.medium)
        #expect(ThemeConstants.Spacing.medium < ThemeConstants.Spacing.regular)
        #expect(ThemeConstants.Spacing.regular < ThemeConstants.Spacing.large)
        #expect(ThemeConstants.Spacing.large < ThemeConstants.Spacing.extraLarge)
        #expect(ThemeConstants.Spacing.extraLarge < ThemeConstants.Spacing.huge)
    }

    // MARK: - Corner Radius Tests

    @Test func testCornerRadiusValuesArePositive() {
        #expect(ThemeConstants.CornerRadius.small > 0)
        #expect(ThemeConstants.CornerRadius.medium > 0)
        #expect(ThemeConstants.CornerRadius.large > 0)
    }

    @Test func testCornerRadiusRoundFunction() {
        #expect(ThemeConstants.CornerRadius.round(100) == 50)
        #expect(ThemeConstants.CornerRadius.round(50) == 25)
        #expect(ThemeConstants.CornerRadius.round(20) == 10)
    }

    // MARK: - Sizing Tests

    @Test func testIconSizesArePositive() {
        #expect(ThemeConstants.Sizing.iconSmall > 0)
        #expect(ThemeConstants.Sizing.iconMedium > 0)
        #expect(ThemeConstants.Sizing.iconLarge > 0)
        #expect(ThemeConstants.Sizing.iconExtraLarge > 0)
    }

    @Test func testIconSizesOrdered() {
        #expect(ThemeConstants.Sizing.iconSmall < ThemeConstants.Sizing.iconMedium)
        #expect(ThemeConstants.Sizing.iconMedium < ThemeConstants.Sizing.iconLarge)
        #expect(ThemeConstants.Sizing.iconLarge < ThemeConstants.Sizing.iconExtraLarge)
    }

    @Test func testButtonAndRowSizes() {
        #expect(ThemeConstants.Sizing.buttonHeight > 0)
    }

    @Test func testSpaceBarSizing() {
        // Buttons fit the bar and leave room around a medium icon.
        #expect(ThemeConstants.Sizing.spaceBarButtonSize <= ThemeConstants.Sizing.spaceBarHeight)
        #expect(ThemeConstants.Sizing.spaceBarButtonSize > ThemeConstants.Sizing.iconMedium)
        // Compact bar: the dot fits its slot, which is narrower than a full one.
        #expect(ThemeConstants.Sizing.spaceBarDotSize < ThemeConstants.Sizing.spaceBarCompactSlotWidth)
        #expect(ThemeConstants.Sizing.spaceBarCompactSlotWidth < ThemeConstants.Sizing.spaceBarButtonSize)
        // Edge dots shrink, but stay visible.
        #expect(ThemeConstants.Sizing.spaceBarEdgeDotMinSize > 0)
        #expect(ThemeConstants.Sizing.spaceBarEdgeDotMinSize < ThemeConstants.Sizing.spaceBarDotSize)
        #expect(ThemeConstants.Sizing.spaceBarEdgeDotRamp > 0)
    }

    // MARK: - Animation Tests

    @Test func testAnimationDurationsArePositive() {
        #expect(ThemeConstants.Animation.durationFast > 0)
        #expect(ThemeConstants.Animation.durationNormal > 0)
        #expect(ThemeConstants.Animation.durationSlow > 0)
    }

    @Test func testAnimationDurationsOrdered() {
        #expect(ThemeConstants.Animation.durationFast < ThemeConstants.Animation.durationNormal)
        #expect(ThemeConstants.Animation.durationNormal < ThemeConstants.Animation.durationSlow)
    }
}
