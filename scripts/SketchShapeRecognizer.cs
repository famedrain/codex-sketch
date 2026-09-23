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
    private const int SampleCount = 64;

    private static double Distance(double x1, double y1, double x2, double y2)
    {
        double dx = x2 - x1;
        double dy = y2 - y1;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    private static double Clamp01(double value)
    {
        return Math.Max(0.0, Math.Min(1.0, value));
    }

    private static double NormalizeAngle(double angle)
    {
        while (angle > Math.PI) angle -= 2.0 * Math.PI;
        while (angle < -Math.PI) angle += 2.0 * Math.PI;
        return angle;
    }

    private static void Resample(double[] xs, double[] ys, int count, out double[] rx, out double[] ry)
    {
        int n = xs.Length;
        double[] cumulative = new double[n];
        for (int i = 1; i < n; i++)
        {
            cumulative[i] = cumulative[i - 1] + Distance(xs[i - 1], ys[i - 1], xs[i], ys[i]);
        }

        double total = cumulative[n - 1];
        rx = new double[count];
        ry = new double[count];
        int segment = 1;
        for (int i = 0; i < count; i++)
        {
            double target = total * i / (count - 1.0);
            while (segment < n - 1 && cumulative[segment] < target) segment++;
            double segmentLength = cumulative[segment] - cumulative[segment - 1];
            double amount = segmentLength <= 0.0001 ? 0.0 : (target - cumulative[segment - 1]) / segmentLength;
            rx[i] = xs[segment - 1] + (xs[segment] - xs[segment - 1]) * amount;
            ry[i] = ys[segment - 1] + (ys[segment] - ys[segment - 1]) * amount;
        }
    }

    private static double Orientation(double ax, double ay, double bx, double by, double cx, double cy)
    {
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    }

    private static bool SegmentsCross(
        double ax, double ay, double bx, double by,
        double cx, double cy, double dx, double dy)
    {
        double o1 = Orientation(ax, ay, bx, by, cx, cy);
        double o2 = Orientation(ax, ay, bx, by, dx, dy);
        double o3 = Orientation(cx, cy, dx, dy, ax, ay);
        double o4 = Orientation(cx, cy, dx, dy, bx, by);
        const double epsilon = 0.0001;
        return ((o1 > epsilon && o2 < -epsilon) || (o1 < -epsilon && o2 > epsilon)) &&
               ((o3 > epsilon && o4 < -epsilon) || (o3 < -epsilon && o4 > epsilon));
    }

    private static int CountSelfIntersections(double[] xs, double[] ys)
    {
        int intersections = 0;
        for (int i = 0; i < xs.Length - 1; i++)
        {
            for (int j = i + 2; j < xs.Length - 1; j++)
            {
                if (i == 0 && j == xs.Length - 2) continue;
                if (SegmentsCross(xs[i], ys[i], xs[i + 1], ys[i + 1], xs[j], ys[j], xs[j + 1], ys[j + 1]))
                {
                    intersections++;
                    if (intersections > 1) return intersections;
                }
            }
        }
        return intersections;
    }

    public static SketchShapeMatch Recognize(double[] xs, double[] ys)
    {
        if (xs == null || ys == null || xs.Length != ys.Length || xs.Length < 3) return null;

        int n = xs.Length;
        double rawPath = 0.0;
        for (int i = 1; i < n; i++) rawPath += Distance(xs[i - 1], ys[i - 1], xs[i], ys[i]);
        if (rawPath < 30.0) return null;

        double[] sx, sy;
        Resample(xs, ys, SampleCount, out sx, out sy);

        double minX = sx[0], maxX = sx[0], minY = sy[0], maxY = sy[0], path = 0.0;
        for (int i = 1; i < SampleCount; i++)
        {
            minX = Math.Min(minX, sx[i]); maxX = Math.Max(maxX, sx[i]);
            minY = Math.Min(minY, sy[i]); maxY = Math.Max(maxY, sy[i]);
            path += Distance(sx[i - 1], sy[i - 1], sx[i], sy[i]);
        }

        double width = maxX - minX, height = maxY - minY;
        double diagonal = Math.Sqrt(width * width + height * height);
        double chord = Distance(sx[0], sy[0], sx[SampleCount - 1], sy[SampleCount - 1]);
        if (diagonal < 20.0) return null;

        if (chord > 35.0)
        {
            double maxDeviation = 0.0, squaredDeviation = 0.0, backwardDistance = 0.0;
            double dx = sx[SampleCount - 1] - sx[0], dy = sy[SampleCount - 1] - sy[0];
            double previousProjection = 0.0;
            for (int i = 0; i < SampleCount; i++)
            {
                double deviation = Math.Abs(dy * sx[i] - dx * sy[i] + sx[SampleCount - 1] * sy[0] - sy[SampleCount - 1] * sx[0]) / chord;
                maxDeviation = Math.Max(maxDeviation, deviation);
                squaredDeviation += deviation * deviation;
                double projection = ((sx[i] - sx[0]) * dx + (sy[i] - sy[0]) * dy) / chord;
                if (i > 0 && projection < previousProjection) backwardDistance += previousProjection - projection;
                previousProjection = projection;
            }

            double rmsDeviation = Math.Sqrt(squaredDeviation / SampleCount);
            double allowedRms = Math.Max(3.0, chord * 0.028);
            double allowedMax = Math.Max(8.0, chord * 0.075);
            double pathRatio = path / chord;
            if (rmsDeviation <= allowedRms && maxDeviation <= allowedMax && pathRatio <= 1.24 && backwardDistance / chord <= 0.08)
            {
                double confidence = 1.0 - Math.Max(
                    Math.Max(rmsDeviation / allowedRms, maxDeviation / allowedMax),
                    Math.Max((pathRatio - 1.0) / 0.24, backwardDistance / chord / 0.08));
                return new SketchShapeMatch
                {
                    Type = "Line",
                    StartX = sx[0], StartY = sy[0],
                    EndX = sx[SampleCount - 1], EndY = sy[SampleCount - 1],
                    Confidence = Clamp01(confidence)
                };
            }
        }

        double maximumClosure = Math.Max(24.0, diagonal * 0.24);
        if (chord > maximumClosure || chord / path > 0.12 || width < 35.0 || height < 35.0) return null;
        if (CountSelfIntersections(sx, sy) > 1) return null;

        double effectivePath = path + chord;
        double shortSide = Math.Min(width, height);
        double edgeError = 0.0;
        int left = 0, right = 0, top = 0, bottom = 0;
        double edgeBand = shortSide * 0.13;
        double cornerBand = shortSide * 0.18;
        bool topLeft = false, topRight = false, bottomLeft = false, bottomRight = false;
        for (int i = 0; i < SampleCount; i++)
        {
            double dl = Math.Abs(sx[i] - minX), dr = Math.Abs(sx[i] - maxX);
            double dt = Math.Abs(sy[i] - minY), db = Math.Abs(sy[i] - maxY);
            edgeError += Math.Min(Math.Min(dl, dr), Math.Min(dt, db));
            if (dl <= edgeBand) left++;
            if (dr <= edgeBand) right++;
            if (dt <= edgeBand) top++;
            if (db <= edgeBand) bottom++;
            if (Distance(sx[i], sy[i], minX, minY) <= cornerBand) topLeft = true;
            if (Distance(sx[i], sy[i], maxX, minY) <= cornerBand) topRight = true;
            if (Distance(sx[i], sy[i], minX, maxY) <= cornerBand) bottomLeft = true;
            if (Distance(sx[i], sy[i], maxX, maxY) <= cornerBand) bottomRight = true;
        }
        edgeError = edgeError / SampleCount / shortSide;
        int sideMinimum = 5;
        double rectangleRatio = effectivePath / (2.0 * (width + height));
        if (edgeError <= 0.085 && rectangleRatio >= 0.78 && rectangleRatio <= 1.28 &&
            left >= sideMinimum && right >= sideMinimum && top >= sideMinimum && bottom >= sideMinimum &&
            topLeft && topRight && bottomLeft && bottomRight)
        {
            double confidence =
                0.55 * Clamp01(1.0 - edgeError / 0.085) +
                0.25 * Clamp01(1.0 - Math.Abs(rectangleRatio - 1.0) / 0.28) +
                0.20 * Clamp01(1.0 - chord / maximumClosure);
            if (confidence >= 0.45)
            {
                return new SketchShapeMatch { Type = "Rectangle", X = minX, Y = minY, Width = width, Height = height, Confidence = confidence };
            }
        }

        double cx = (minX + maxX) / 2.0, cy = (minY + maxY) / 2.0;
        double rx = width / 2.0, ry = height / 2.0;
        double axisRatio = Math.Min(rx, ry) / Math.Max(rx, ry);
        if (axisRatio < 0.25) return null;

        double radialError = 0.0, maxRadialError = 0.0;
        int[] quadrants = new int[4];
        double totalTurn = 0.0, absoluteTurn = 0.0;
        double previousAngle = Math.Atan2((sy[0] - cy) / ry, (sx[0] - cx) / rx);
        for (int i = 0; i < SampleCount; i++)
        {
            double nx = (sx[i] - cx) / rx, ny = (sy[i] - cy) / ry;
            double error = Math.Abs(Math.Sqrt(nx * nx + ny * ny) - 1.0);
            radialError += error;
            maxRadialError = Math.Max(maxRadialError, error);
            quadrants[(nx >= 0.0 ? 1 : 0) + (ny >= 0.0 ? 2 : 0)]++;

            if (i > 0)
            {
                double angle = Math.Atan2(ny, nx);
                double turn = NormalizeAngle(angle - previousAngle);
                totalTurn += turn;
                absoluteTurn += Math.Abs(turn);
                previousAngle = angle;
            }
        }
        double closingAngle = Math.Atan2((sy[0] - cy) / ry, (sx[0] - cx) / rx);
        double closingTurn = NormalizeAngle(closingAngle - previousAngle);
        totalTurn += closingTurn;
        absoluteTurn += Math.Abs(closingTurn);
        radialError /= SampleCount;

        double h = Math.Pow(rx - ry, 2.0) / Math.Pow(rx + ry, 2.0);
        double expectedCircumference = Math.PI * (rx + ry) * (1.0 + 3.0 * h / (10.0 + Math.Sqrt(4.0 - 3.0 * h)));
        double ellipseRatio = effectivePath / expectedCircumference;
        double directionConsistency = absoluteTurn <= 0.0001 ? 0.0 : Math.Abs(totalTurn) / absoluteTurn;
        double winding = Math.Abs(totalTurn) / (2.0 * Math.PI);
        bool hasQuadrantCoverage = quadrants[0] >= 4 && quadrants[1] >= 4 && quadrants[2] >= 4 && quadrants[3] >= 4;

        if (radialError <= 0.13 && maxRadialError <= 0.38 &&
            ellipseRatio >= 0.78 && ellipseRatio <= 1.25 &&
            directionConsistency >= 0.88 && winding >= 0.78 && winding <= 1.22 && hasQuadrantCoverage)
        {
            double confidence =
                0.50 * Clamp01(1.0 - radialError / 0.13) +
                0.15 * Clamp01(1.0 - maxRadialError / 0.38) +
                0.20 * Clamp01((directionConsistency - 0.88) / 0.12) +
                0.15 * Clamp01(1.0 - Math.Abs(ellipseRatio - 1.0) / 0.25);
            if (confidence >= 0.45)
            {
                double ratio = width / height;
                string type = ratio >= 0.78 && ratio <= 1.28 ? "Circle" : "Ellipse";
                if (type == "Circle")
                {
                    double diameter = (width + height) / 2.0;
                    return new SketchShapeMatch { Type = type, X = cx - diameter / 2.0, Y = cy - diameter / 2.0, Width = diameter, Height = diameter, Confidence = confidence };
                }
                return new SketchShapeMatch { Type = type, X = minX, Y = minY, Width = width, Height = height, Confidence = confidence };
            }
        }

        return null;
    }
}
