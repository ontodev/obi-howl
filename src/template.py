#!/usr/bin/env python3

# Convert a TSV table into a HOWL file
# consisting of lines
# that append the header to the cell value.

import argparse, csv


def main():
  # Parse arguments
  parser = argparse.ArgumentParser(
      description='Convert table to HOWL stanzas')
  parser.add_argument('table',
      type=argparse.FileType('r'),
      help='a TSV file')
  args = parser.parse_args()

  rows = csv.reader(args.table, delimiter='\t')
  headers = next(rows)
  for row in rows:
    class_type = 'subclass of'
    equivalents = []
    if len(row) < 1:
      continue
    for i in range(0, min(len(headers), len(row))):
      if headers[i].strip() == '':
        continue
      if row[i].strip() == '':
        continue
      if headers[i] == 'CLASS_TYPE':
        class_type = row[i]
        continue
      if headers[i] == 'SUBJECT':
        print(row[i])
      elif headers[i].startswith(':>> '):
        value = row[i]
        if ' ' in value and not value.startswith('(') and not value.startswith("'"):
          value = "'" + value + "'"
        if class_type == 'subclass of':
          print('subclass of' + headers[i].replace('%', value))
        elif class_type == 'equivalent to':
          equivalents.append(headers[i].lstrip(':> ').replace('%', value))
      elif '%' in headers[i]:
        print(headers[i].replace('%', row[i]))
      else:
        print(headers[i] +' '+ row[i])
    if len(equivalents) > 0:
      print('equivalent to:>> ' + ' and '.join(equivalents))
    print()


# Run the main() function.
if __name__ == "__main__":
  main()
