#!/usr/bin/env venv/bin/python
import argparse
import os
import re


def unpack_files(input_file, output_dir):
    """
    Unpacks a single file containing multiple .swift, .plist, .json, or .entitlements
    files back into a directory structure.
    """
    if not os.path.exists(input_file):
        print(f"Error: Input file not found at {input_file}")
        return

    os.makedirs(output_dir, exist_ok=True)

    with open(input_file, "r") as infile:
        content = infile.read()

    # Find all file markers and their positions
    markers = list(re.finditer(r"// FILE: (.*)\n", content))

    if not markers:
        print("No file markers found in the input file.")
        return

    file_count = 0
    for i, match in enumerate(markers):
        filename = match.group(1)
        start_pos = match.end()
        end_pos = markers[i + 1].start() if i + 1 < len(markers) else len(content)

        file_content = content[start_pos:end_pos].strip("\n")

        output_path = os.path.join(output_dir, filename)
        with open(output_path, "w") as outfile:
            outfile.write(file_content)
        file_count += 1
        print(f"Created {output_path}")

    print(f"\nSuccessfully unpacked {file_count} files into {output_dir}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Unpack a single file into multiple source files.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("input_file", help="The input file to unpack.")
    parser.add_argument("output_dir", help="The directory to unpack files into.")
    args = parser.parse_args()

    unpack_files(args.input_file, args.output_dir)
