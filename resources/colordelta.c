/*
** A SQLite extension for calculating the CIELAB ΔE* (CIE76) distance
* * between two colors specified as comma-delimited sRGB strings.
**
** Conversion formulas courtesy of EasyRGB. See
** https://www.easyrgb.com/en/math.php
**
** The SQLite-facing parts are copied from ext/misc/rot13.c in the
** SQLite Fossil repository.
**/

#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <inttypes.h>

/*
** Convert a comma-delimted RGB string to a Lab color array.
*/
void rgbToLab(const unsigned char *triple, float *ret)
{
  char *tripletmp;
  char red[4], green[4], blue[4];
  float tmp[3];
  float xyz[3];

  tripletmp = strdup(triple);

  strcpy(red, strtok(tripletmp, ","));
  strcpy(green, strtok(NULL, ","));
  strcpy(blue, strtok(NULL, ","));
  free(tripletmp);

  tmp[0] = strtof(red, NULL);
  tmp[1] = strtof(green, NULL);
  tmp[2] = strtof(blue, NULL);

  // RGB to XYZ
  for (int i = 0; i < 3; i++) {
    tmp[i] /= 255;

    if (tmp[i] > 0.04045) {
      tmp[i] = pow((tmp[i] + 0.055) / 1.055, 2.4);
    } else {
      tmp[i] /= 12.92;
    }

    tmp[i] *= 100;
  }

  xyz[0] = tmp[0] * 0.4124 + tmp[1] * 0.3576 + tmp[2] * 0.1805;
  xyz[1] = tmp[0] * 0.2126 + tmp[1] * 0.7152 + tmp[2] * 0.0722;
  xyz[2] = tmp[0] * 0.0193 + tmp[1] * 0.1192 + tmp[2] * 0.9505;

  // XYZ to Lab
  tmp[0] = xyz[0] / 95.047;
  tmp[1] = xyz[1] / 100.000;
  tmp[2] = xyz[2] / 108.883;

  for (int i = 0; i < 3; i++) {
    if (tmp[i] > 0.008856) {
      tmp[i] = pow(tmp[i], 1.0/3.0);
    } else {
      tmp[i] = (7.787 * tmp[i]) + (16/116);
    }
  }

  ret[0] = (116 * tmp[1]) - 16;
  ret[1] = 500 * (tmp[0] - tmp[1]);
  ret[2] = 200 * (tmp[1] - tmp[2]);
}

/*
** Calculate the Delta-E (1976) of two comma-delimited RGB strings.
*/
static float colorDelta(const unsigned char *rgb1, const  unsigned char *rgb2)
{
  float lab1[3], lab2[3];
  float sumOfSquares = 0;
  rgbToLab(rgb1, lab1);
  rgbToLab(rgb2, lab2);

  sumOfSquares += pow(lab1[0] - lab2[0], 2);
  sumOfSquares += pow(lab1[1] - lab2[1], 2);
  sumOfSquares += pow(lab1[2] - lab2[2], 2);

  return sqrt(sumOfSquares);
}

/*
** The colordelta function exposed to SQLite.
*/
static void sqlite3_colordelta_function(
  sqlite3_context *context,
  int argc,
  sqlite3_value **argv
) {
  const unsigned char *zIn, *zIn2;
  zIn = (const unsigned char*)sqlite3_value_text(argv[0]);
  zIn2 = (const unsigned char*)sqlite3_value_text(argv[1]);

  const double zOut = colorDelta(zIn, zIn2);

  sqlite3_result_double(context, zOut);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_colordelta_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
  int rc = SQLITE_OK;

  SQLITE_EXTENSION_INIT2(pApi);

  (void)pzErrMsg;

  rc = sqlite3_create_function(db, "colordelta", 2,
                               SQLITE_UTF8,
                               0,
                               sqlite3_colordelta_function,
                               0, 0);

   return rc;
}
