#!/usr/bin/env python3
"""Знімок графіків панелі CloudWatch у PNG з вертикальними мітками (A–E тощо).

Графіки рендерить сам CloudWatch (GetMetricWidgetImage), скрипт лише додає мітки
і складає їх у сітку.

  AWS_PROFILE=lab1-personal python3 scripts/dashboard_png.py \
      --start 2026-11-12T21:10:00Z --end 2026-11-12T21:50:00Z \
      --widgets 0,1,2,3,4,5 --mark A=2026-11-12T21:12:00Z --mark B=... \
      --out docs/img/dashboard-run.png
"""
import argparse
import copy
import io
import json
import subprocess

from PIL import Image, ImageDraw, ImageFont


def aws(*args, binary=False):
    out = subprocess.run(["aws", *args], check=True, capture_output=True)
    return out.stdout if binary else out.stdout.decode()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dashboard", default="lab1-books")
    p.add_argument("--start", required=True)
    p.add_argument("--end", required=True)
    p.add_argument("--widgets", default="0,1,2,3,4,5")
    p.add_argument("--mark", action="append", default=[], help="LABEL=ISO-час")
    p.add_argument("--cols", type=int, default=2)
    p.add_argument("--width", type=int, default=800)
    p.add_argument("--height", type=int, default=360)
    p.add_argument("--title", default="")
    p.add_argument("--out", required=True)
    a = p.parse_args()

    body = json.loads(aws("cloudwatch", "get-dashboard", "--dashboard-name", a.dashboard,
                          "--query", "DashboardBody", "--output", "text"))
    marks = [dict(zip(("label", "value"), m.split("=", 1))) for m in a.mark]

    images = []
    for i in (int(x) for x in a.widgets.split(",")):
        props = copy.deepcopy(body["widgets"][i]["properties"])
        ann = props.setdefault("annotations", {})
        ann["vertical"] = ann.get("vertical", []) + marks
        props.update(start=a.start, end=a.end, width=a.width, height=a.height, timezone="+0000")
        png = aws("cloudwatch", "get-metric-widget-image", "--metric-widget", json.dumps(props),
                  "--output-format", "png", "--query", "MetricWidgetImage", "--output", "text")
        import base64
        images.append(Image.open(io.BytesIO(base64.b64decode(png))).convert("RGB"))

    rows = (len(images) + a.cols - 1) // a.cols
    head = 50 if a.title else 0
    sheet = Image.new("RGB", (a.cols * a.width, head + rows * a.height), "white")
    for n, img in enumerate(images):
        sheet.paste(img, ((n % a.cols) * a.width, head + (n // a.cols) * a.height))
    if a.title:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
        ImageDraw.Draw(sheet).text((16, 12), a.title, fill="black", font=font)
    sheet.save(a.out)
    print(a.out, sheet.size)


if __name__ == "__main__":
    main()
