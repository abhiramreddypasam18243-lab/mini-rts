## Statistics for the strategy experiment (SPEC 16; AC-70). This is analysis
## code outside the simulation, so floating point is fine here.
class_name Stats
extends RefCounted

const Z95: float = 1.959964


## Wilson score interval for `wins` successes out of `n` (decision D-13):
##   centre = (p + z²/2n) / (1 + z²/n)
##   margin = z * sqrt(p(1-p)/n + z²/4n²) / (1 + z²/n)
## Unlike the normal approximation it stays inside [0, 1] and does not
## collapse to zero width at 0 % or 100 %. With no data it returns [0, 1].
static func wilson(wins: int, n: int, z: float = Z95) -> Vector2:
	if n <= 0:
		return Vector2(0.0, 1.0)
	var p: float = float(wins) / n
	var z2: float = z * z
	var denom: float = 1.0 + z2 / n
	var centre: float = (p + z2 / (2.0 * n)) / denom
	var margin: float = z * sqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n)) / denom
	return Vector2(maxf(centre - margin, 0.0), minf(centre + margin, 1.0))


static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s: float = 0.0
	for v: Variant in values:
		s += float(v)
	return s / values.size()


## Two-sided sign test p-value: the chance of a split at least this uneven
## between `a` and `b` if both were equally likely (ties dropped).
static func sign_test(a: int, b: int) -> float:
	var n: int = a + b
	if n == 0:
		return 1.0
	var k: int = mini(a, b)
	var tail: float = 0.0
	for i: int in k + 1:
		tail += _binom(n, i)
	return minf(1.0, 2.0 * tail / pow(2.0, n))


static func _binom(n: int, k: int) -> float:
	var r: float = 1.0
	for i: int in k:
		r = r * (n - i) / (i + 1)
	return r
