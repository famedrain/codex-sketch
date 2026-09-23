using System;

public sealed class SketchShapeMatch
{
    public string Type { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
    public double Width { get; set; }
    public double Height { get; set; }
    public double StartX { get; set; }
    public double StartY { get; set; }
    public double EndX { get; set; }
    public double EndY { get; set; }
    public double Confidence { get; set; }
}

public static class SketchShapeRecognizer
{
    private static double Distance(double x1, double y1, double x2, double y2)
    {
        double dx = x2 - x1;
        double dy = y2 - y1;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public static SketchShapeMatch Recognize(double[] xs, double[] ys)
    {
        if (xs == null || ys == null || xs.Length != ys.Length || xs.Length < 3) return null;

        int n = xs.Length;
        double minX = xs[0], maxX = xs[0], minY = ys[0], maxY = ys[0], path = 0.0;
        for (int i = 1; i < n; i++)
        {
            minX = Math.Min(minX, xs[i]); maxX = Math.Max(maxX, xs[i]);
            minY = Math.Min(minY, ys[i]); maxY = Math.Max(maxY, ys[i]);
            path += Distance(xs[i - 1], ys[i - 1], xs[i], ys[i]);
        }

        double width = maxX - minX, height = maxY - minY;
        double diagonal = Math.Sqrt(width * width + height * height);
        double chord = Distance(xs[0], ys[0], xs[n - 1], ys[n - 1]);
        if (path < 30.0 || diagonal < 20.0) return null;

        if (chord > 35.0 && path / chord <= 1.10)
        {
            double maxDeviation = 0.0;
            for (int i = 1; i < n - 1; i++)
            {
                double deviation = Math.Abs((ys[n - 1] - ys[0]) * xs[i] - (xs[n - 1] - xs[0]) * ys[i] + xs[n - 1] * ys[0] - ys[n - 1] * xs[0]) / chord;
                maxDeviation = Math.Max(maxDeviation, deviation);
            }
            double allowed = Math.Max(4.0, chord * 0.04);
            if (maxDeviation <= allowed)
            {
                return new SketchShapeMatch { Type = "Line", StartX = xs[0], StartY = ys[0], EndX = xs[n - 1], EndY = ys[n - 1], Confidence = 1.0 - maxDeviation / allowed };
            }
        }

        double closure = Distance(xs[0], ys[0], xs[n - 1], ys[n - 1]);
        if (closure > Math.Max(16.0, diagonal * 0.12) || width < 35.0 || height < 35.0) return null;

        double shortSide = Math.Min(width, height);
        double edgeError = 0.0;
        int left = 0, right = 0, top = 0, bottom = 0;
        double edgeBand = shortSide * 0.11;
        for (int i = 0; i < n; i++)
        {
            double dl = Math.Abs(xs[i] - minX), dr = Math.Abs(xs[i] - maxX);
            double dt = Math.Abs(ys[i] - minY), db = Math.Abs(ys[i] - maxY);
            edgeError += Math.Min(Math.Min(dl, dr), Math.Min(dt, db));
            if (dl <= edgeBand) left++;
            if (dr <= edgeBand) right++;
            if (dt <= edgeBand) top++;
            if (db <= edgeBand) bottom++;
        }
        edgeError = edgeError / n / shortSide;
        int sideMinimum = Math.Max(2, n / 14);
        double perimeterRatio = path / (2.0 * (width + height));
        if (edgeError <= 0.055 && perimeterRatio >= 0.90 && perimeterRatio <= 1.18 && left >= sideMinimum && right >= sideMinimum && top >= sideMinimum && bottom >= sideMinimum)
        {
            return new SketchShapeMatch { Type = "Rectangle", X = minX, Y = minY, Width = width, Height = height, Confidence = 1.0 - edgeError / 0.055 };
        }

        double cx = (minX + maxX) / 2.0, cy = (minY + maxY) / 2.0;
        double rx = width / 2.0, ry = height / 2.0;
        double radialError = 0.0, maxRadialError = 0.0;
        for (int i = 0; i < n; i++)
        {
            double nx = (xs[i] - cx) / rx, ny = (ys[i] - cy) / ry;
            double error = Math.Abs(Math.Sqrt(nx * nx + ny * ny) - 1.0);
            radialError += error;
            maxRadialError = Math.Max(maxRadialError, error);
        }
        radialError /= n;
        if (radialError <= 0.10 && maxRadialError <= 0.28)
        {
            double ratio = width / height;
            string type = ratio >= 0.85 && ratio <= 1.18 ? "Circle" : "Ellipse";
            if (type == "Circle")
            {
                double diameter = (width + height) / 2.0;
                return new SketchShapeMatch { Type = type, X = cx - diameter / 2.0, Y = cy - diameter / 2.0, Width = diameter, Height = diameter, Confidence = 1.0 - radialError / 0.10 };
            }
            return new SketchShapeMatch { Type = type, X = minX, Y = minY, Width = width, Height = height, Confidence = 1.0 - radialError / 0.10 };
        }

        return null;
    }
}
