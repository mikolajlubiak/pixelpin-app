import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:dither_it/dither_it.dart';

void convertImage(
    img.Image image, Uint8List monoBuffer, Uint8List colorBuffer) {
  const bool with_color = true;

  int width = image.width;
  int height = image.height;

  Uint8List rgbBytes = image.getBytes(order: img.ChannelOrder.rgb);

  int red, green, blue;
  bool whitish = false;
  bool colored = false;
  int out_byte = 0xFF; // white
  int out_color_byte = 0xFF; // no color
  int out_col_idx = 0;

  for (int row = 0; row < height; row++) {
    out_col_idx = 0;
    for (int col = 0; col < width; col++) {
      int index = (row * width + col) * 3;
      red = rgbBytes[index];
      green = rgbBytes[index + 1];
      blue = rgbBytes[index + 2];

      whitish = (red * 0.299 + green * 0.587 + blue * 0.114) > 0x80; // whitish

      colored = ((red > 0x80) &&
              (((red > green + 0x40) && (red > blue + 0x40)) ||
                  (red + 0x10 > green + blue))) ||
          (green > 0xC8 && red > 0xC8 && blue < 0x40); // reddish or yellowish?

      if (whitish) {
        // keep white
      } else if (colored && with_color) {
        out_color_byte &= ~(0x80 >> col % 8); // colored
      } else {
        out_byte &= ~(0x80 >> col % 8); // black
      }
      if ((7 == col % 8) ||
          (col == width - 1)) // write that last byte! (for w%8!=0 border)
      {
        monoBuffer[row * (width / 8).ceil() + out_col_idx] = out_byte;
        colorBuffer[row * (width / 8).ceil() + out_col_idx] = out_color_byte;
        out_col_idx++;
        out_byte = 0xFF; // white (for w%8!=0 border)
        out_color_byte = 0xFF; // white (for w%8!=0 border)
      }
    }
  }
}

img.Image noDither(img.Image image) {
  return image;
}

img.Image ditherFloydSteinberg(img.Image image) {
  return DitherIt.floydSteinberg(image: image);
}

img.Image ditherOrdered(img.Image image) {
  return DitherIt.ordered(image: image, matrixSize: 8);
}

img.Image ditherRiemersma(img.Image image) {
  return DitherIt.riemersma(image: image, historySize: 16);
}
