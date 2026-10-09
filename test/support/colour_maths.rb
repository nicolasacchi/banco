# Colour maths for the lesson palette test (D-246): WCAG contrast, colour-vision-deficiency simulation
# (Machado, Oliveira and Fernandes 2009, severity 1.0) and CIEDE2000. Pure; hex strings in, numbers out.
module ColourMaths
  CVD = {
    protanopia: [ [ 0.152286, 1.052583, -0.204868 ], [ 0.114503, 0.786281, 0.099216 ], [ -0.003882, -0.048116, 1.051998 ] ],
    deuteranopia: [ [ 0.367322, 0.860646, -0.227968 ], [ 0.280085, 0.672501, 0.047413 ], [ -0.011820, 0.042940, 0.968881 ] ],
    tritanopia: [ [ 1.255528, -0.076749, -0.178779 ], [ -0.078411, 0.930809, 0.147602 ], [ 0.004733, 0.691367, 0.303900 ] ]
  }.freeze
  D65 = [ 0.95047, 1.0, 1.08883 ].freeze

  module_function

  def rgb(hex) = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }

  def linear(c) = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4

  def lin(hex) = rgb(hex).map { |c| linear(c) }

  def luminance(hex)
    r, g, b = lin(hex)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].max, [ luminance(a), luminance(b) ].min
    (hi + 0.05) / (lo + 0.05)
  end

  def simulate(lin_rgb, kind)
    CVD.fetch(kind).map { |row| row.zip(lin_rgb).sum { |m, c| m * c }.clamp(0.0, 1.0) }
  end

  def xyz(lin_rgb)
    r, g, b = lin_rgb
    [ 0.4124564 * r + 0.3575761 * g + 0.1804375 * b, 0.2126729 * r + 0.7151522 * g + 0.0721750 * b, 0.0193339 * r + 0.1191920 * g + 0.9503041 * b ]
  end

  def lab(lin_rgb)
    f = ->(t) { t > (6.0 / 29)**3 ? Math.cbrt(t) : t / (3 * (6.0 / 29)**2) + 4.0 / 29 }
    x, y, z = xyz(lin_rgb).zip(D65).map { |v, w| f.call(v / w) }
    [ 116 * y - 16, 500 * (x - y), 200 * (y - z) ]
  end

  # CIEDE2000 (Sharma, Wu and Dalal 2005), kL = kC = kH = 1.
  def delta_e(lab1, lab2)
    l1, a1, b1 = lab1
    l2, a2, b2 = lab2
    c1 = Math.hypot(a1, b1)
    c2 = Math.hypot(a2, b2)
    cbar7 = (((c1 + c2) / 2)**7)
    g = 0.5 * (1 - Math.sqrt(cbar7 / (cbar7 + 25.0**7)))
    ap1 = (1 + g) * a1
    ap2 = (1 + g) * a2
    cp1 = Math.hypot(ap1, b1)
    cp2 = Math.hypot(ap2, b2)
    hp = ->(b, ap) { b.zero? && ap.zero? ? 0.0 : (Math.atan2(b, ap) * 180 / Math::PI) % 360 }
    hp1 = hp.call(b1, ap1)
    hp2 = hp.call(b2, ap2)
    dl = l2 - l1
    dc = cp2 - cp1
    dh = if cp1 * cp2 == 0 then 0.0
    elsif (hp2 - hp1).abs <= 180 then hp2 - hp1
    elsif hp2 - hp1 > 180 then hp2 - hp1 - 360
    else hp2 - hp1 + 360
    end
    dhh = 2 * Math.sqrt(cp1 * cp2) * Math.sin(dh * Math::PI / 360)
    lbar = (l1 + l2) / 2
    cbar = (cp1 + cp2) / 2
    hbar = if cp1 * cp2 == 0 then hp1 + hp2
    elsif (hp1 - hp2).abs <= 180 then (hp1 + hp2) / 2
    elsif hp1 + hp2 < 360 then (hp1 + hp2 + 360) / 2
    else (hp1 + hp2 - 360) / 2
    end
    rad = ->(d) { d * Math::PI / 180 }
    t = 1 - 0.17 * Math.cos(rad.call(hbar - 30)) + 0.24 * Math.cos(rad.call(2 * hbar)) + 0.32 * Math.cos(rad.call(3 * hbar + 6)) - 0.20 * Math.cos(rad.call(4 * hbar - 63))
    sl = 1 + 0.015 * (lbar - 50)**2 / Math.sqrt(20 + (lbar - 50)**2)
    sc = 1 + 0.045 * cbar
    sh = 1 + 0.015 * cbar * t
    dtheta = 30 * Math.exp(-(((hbar - 275) / 25)**2))
    rc = 2 * Math.sqrt(cbar**7 / (cbar**7 + 25.0**7))
    rt = -Math.sin(rad.call(2 * dtheta)) * rc
    Math.sqrt((dl / sl)**2 + (dc / sc)**2 + (dhh / sh)**2 + rt * (dc / sc) * (dhh / sh))
  end

  # The smallest CIEDE2000 between two colours under the three simulations.
  def cvd_distance(hex_a, hex_b)
    CVD.keys.map { |kind| delta_e(lab(simulate(lin(hex_a), kind)), lab(simulate(lin(hex_b), kind))) }.min
  end
end
