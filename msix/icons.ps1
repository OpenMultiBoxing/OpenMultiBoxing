# Square44x44Logo.targetsize-*_altform-{lightunplated,unplated}.png icons from the website's 1080px logo:
#   msix\icons.ps1 [-Source ..\WebSite-OMB\OpenMultiBoxing.png] [-Out msix\Assets] [-Gray 208]
# lightunplated (light mode): the logo resized. unplated (dark mode): the same with the black turned light gray, the
# orange kept: Windows skips an unplated icon it finds too dark for a dark background (and falls back to the blurry
# 44px Square44x44Logo.png). pack.ps1 adds plain targetsize copies of the lightunplated ones.
param(
    [string]$Source = (Join-Path $PSScriptRoot '..\..\WebSite-OMB\OpenMultiBoxing.png'),
    [string]$Out = (Join-Path $PSScriptRoot Assets),
    [int]$Gray = 208
)
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class StoreIcons {
  public static Bitmap Resize(Image src, int n) {
    var b = new Bitmap(n, n, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.CompositingQuality = CompositingQuality.HighQuality;
      g.Clear(Color.Transparent);
      g.DrawImage(src, 0, 0, n, n);
    }
    return b;
  }
  // Black ink -> gray, blended by the red channel (the logos are black and orange, R=255), alpha unchanged
  public static void GrayInk(Bitmap b, int gray) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int n = d.Stride * d.Height; var px = new byte[n];
    Marshal.Copy(d.Scan0, px, 0, n);
    for (int i = 0; i < n; i += 4) {   // B G R A
      if (px[i + 3] == 0) continue;
      double t = px[i + 2] / 255.0;
      for (int c = 0; c < 3; c++) px[i + c] = (byte)Math.Round(t * px[i + c] + (1 - t) * gray);
    }
    Marshal.Copy(px, 0, d.Scan0, n);
    b.UnlockBits(d);
  }
}
"@
$img = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
try {
    foreach ($n in 16, 24, 32, 48, 256) {
        $b = [StoreIcons]::Resize($img, $n)
        $b.Save((Join-Path $Out "Square44x44Logo.targetsize-${n}_altform-lightunplated.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        [StoreIcons]::GrayInk($b, $Gray)
        $b.Save((Join-Path $Out "Square44x44Logo.targetsize-${n}_altform-unplated.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $b.Dispose()
    }
} finally {
    $img.Dispose()
}
