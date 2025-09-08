#!/usr/bin/env venv/bin/python
import argparse
import os
import glob


def pack_files(source_dir, output_file):
    """
    Packs all .swift, .plist, .json, and .entitlements files from a source directory into a single file.
    A header is added to denote the start of each file's content.
    """
    if not os.path.isdir(source_dir):
        print(f"Error: Source directory not found at {source_dir}")
        return

    # Find all relevant files
    swift_files = glob.glob(os.path.join(source_dir, "*.swift"))
    plist_files = glob.glob(os.path.join(source_dir, "*.plist"))
    json_files = glob.glob(os.path.join(source_dir, "*.json"))
    entitlements_files = glob.glob(os.path.join(source_dir, "*.entitlements"))

    all_files = sorted(swift_files + plist_files + json_files + entitlements_files)

    if not all_files:
        print(f"No .swift, .plist, .json, or .entitlements files found in {source_dir}")
        return

    with open(output_file, "w") as outfile:
        for i, filepath in enumerate(all_files):
            filename = os.path.basename(filepath)
            outfile.write(f"// FILE: {filename}\n")
            with open(filepath, "r") as infile:
                outfile.write(infile.read())
            if i < len(all_files) - 1:
                outfile.write("\n")

    print(f"Successfully packed {len(all_files)} files into {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Pack .swift, .plist, .json, and .entitlements files into a single file.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("source_dir", help="The source directory containing the files.")
    parser.add_argument("output_file", help="The path for the output file.")
    args = parser.parse_args()

    pack_files(args.source_dir, args.output_file)
