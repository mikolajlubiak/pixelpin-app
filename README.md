![Logo icon](docs/icon.png "Logo icon")

# PixelPin app

Flutter companion app for [PixelPin](https://github.com/mikolajlubiak/pixelpin), a wearable Bluetooth e-paper badge. It finds the badge over Bluetooth Low Energy, prepares an image for its 2.9-inch 128×296 black/white/red e-paper panel and streams it with the badge's custom protocol. The firmware, wiring and protocol specification live in the [pixelpin](https://github.com/mikolajlubiak/pixelpin) repository.

## Showcase

<h3 align="center">Device</h3>
<p align="center">
  <a href="docs/epd2.jpg"><img src="docs/epd2.jpg" height="220" alt="E-Paper showcase 2"></a>
  <a href="docs/epd6.jpg"><img src="docs/epd6.jpg" height="220" alt="E-Paper showcase 6"></a>
</p>

<p align="center">
  <a href="docs/epd1.jpg"><img src="docs/epd1.jpg" height="220" alt="E-Paper showcase 1"></a>
  <a href="docs/epd3.jpg"><img src="docs/epd3.jpg" height="220" alt="E-Paper showcase 3"></a>
  <a href="docs/epd4.jpg"><img src="docs/epd4.jpg" height="220" alt="E-Paper showcase 4"></a>
  <a href="docs/epd5.jpg"><img src="docs/epd5.jpg" height="220" alt="E-Paper showcase 5"></a>
  <a href="docs/epd7.jpg"><img src="docs/epd7.jpg" height="220" alt="E-Paper showcase 7"></a>
</p>

<h3 align="center">App</h3>
<p align="center">
  <a href="docs/app1.jpg"><img src="docs/app1.jpg" height="220" alt="App showcase 1"></a>
  <a href="docs/app2.jpg"><img src="docs/app2.jpg" height="220" alt="App showcase 2"></a>
</p>

## What the app does

1. **Scan and connect:** scans for devices advertising the PixelPin service UUID and connects with flutter_reactive_ble, requesting a 512-byte MTU.
2. **Prepare the image:** decodes the picked file, rotates landscape images by 90°, resizes to 128 px wide and crops to 128×296.
3. **Dither (optional):** Floyd–Steinberg, ordered (8×8 matrix) or Riemersma dithering through the [dither_it](https://github.com/Penfore/dither_it) package, with a preview of the result.
4. **Convert:** classifies every pixel as white (luma above 128), red (red-dominant) or black and packs the result into two 1-bit planes, MSB first: 4,736 bytes each for the panel's black and red layers.
5. **Upload:** switches the connection to high priority, sends `BEGIN`, both planes in 512-byte writes, `END` and `DRAW`, then drops back to a low-power connection.

## Tech Stack

`Dart` `Flutter` `Bluetooth Low Energy` `flutter_reactive_ble` `image` `dither_it`

## Build

- Install Flutter 3.35.5 (pinned in `.fvmrc`; with [FVM](https://fvm.app/), run `fvm install` and use `fvm flutter`)
- `git clone https://github.com/mikolajlubiak/pixelpin-app`
- `cd pixelpin-app`
- `flutter pub get`
- Connect an Android or iOS device and run `flutter run`

## Credits

- Built with [flutter_reactive_ble](https://github.com/PhilipsHue/flutter_reactive_ble), [image](https://pub.dev/packages/image) and [dither_it](https://github.com/Penfore/dither_it) (MIT).
- Third-party license notices are in [NOTICE](NOTICE).
