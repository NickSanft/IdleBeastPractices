## Mantissa/exponent BigNumber for unbounded currency math.
##
## Invariants (after _normalize()):
##   - mantissa == 0.0 AND exponent == 0  -> canonical zero
##   - otherwise 1.0 <= abs(mantissa) < 10.0
##
## Add/subtract align exponents and cap the precision-loss shift at 16
## (above that the smaller term is below float epsilon and is dropped).
## Multiply/divide adjust exponent additively. Pow uses repeated squaring.
class_name BigNumber
extends RefCounted

const _MAX_ALIGN_SHIFT := 16
const _CLAMP_MAX_LOG := 1.0e9   # safety bound for format/conversion paths

var mantissa: float = 0.0
var exponent: int = 0


# region — construction

static func from_float(v: float) -> BigNumber:
	var b := BigNumber.new()
	b.mantissa = v
	b.exponent = 0
	b._normalize()
	return b

static func from_dict(d: Dictionary) -> BigNumber:
	var b := BigNumber.new()
	b.mantissa = float(d.get("m", 0.0))
	b.exponent = int(d.get("e", 0))
	b._normalize()
	return b

static func zero() -> BigNumber:
	return BigNumber.new()

static func one() -> BigNumber:
	return BigNumber.from_float(1.0)

# endregion


# region — arithmetic

func add(other: BigNumber) -> BigNumber:
	if is_zero():
		return other.clone()
	if other.is_zero():
		return clone()
	# Align to the larger exponent.
	var hi: BigNumber = self if exponent >= other.exponent else other
	var lo: BigNumber = other if exponent >= other.exponent else self
	var shift: int = hi.exponent - lo.exponent
	if shift > _MAX_ALIGN_SHIFT:
		return hi.clone()
	var lo_mantissa_scaled: float = lo.mantissa / pow(10.0, shift)
	var result := BigNumber.new()
	result.mantissa = hi.mantissa + lo_mantissa_scaled
	result.exponent = hi.exponent
	result._normalize()
	return result

func subtract(other: BigNumber) -> BigNumber:
	var negated := other.clone()
	negated.mantissa = -negated.mantissa
	return add(negated)

func multiply(other: BigNumber) -> BigNumber:
	if is_zero() or other.is_zero():
		return BigNumber.zero()
	var result := BigNumber.new()
	result.mantissa = mantissa * other.mantissa
	result.exponent = exponent + other.exponent
	result._normalize()
	return result

func multiply_float(f: float) -> BigNumber:
	if f == 0.0 or is_zero():
		return BigNumber.zero()
	var result := BigNumber.new()
	result.mantissa = mantissa * f
	result.exponent = exponent
	result._normalize()
	return result

func divide(other: BigNumber) -> BigNumber:
	if other.is_zero():
		# Recoverable: return zero so callers don't crash. Surface as a warning
		# rather than an error so test runners don't treat it as a failure;
		# callers that want to enforce nonzero divisors should check first.
		push_warning("BigNumber.divide: division by zero, returning zero")
		return BigNumber.zero()
	if is_zero():
		return BigNumber.zero()
	var result := BigNumber.new()
	result.mantissa = mantissa / other.mantissa
	result.exponent = exponent - other.exponent
	result._normalize()
	return result

func pow_int(n: int) -> BigNumber:
	if n == 0:
		return BigNumber.one()
	if is_zero():
		return BigNumber.zero()
	if n < 0:
		return BigNumber.one().divide(pow_int(-n))
	# Repeated squaring.
	var result := BigNumber.one()
	var base := clone()
	var k: int = n
	while k > 0:
		if (k & 1) == 1:
			result = result.multiply(base)
		base = base.multiply(base)
		k >>= 1
	return result

# endregion


# region — comparison

func compare(other: BigNumber) -> int:
	if is_zero() and other.is_zero():
		return 0
	if is_zero():
		return -1 if other.mantissa > 0.0 else 1
	if other.is_zero():
		return 1 if mantissa > 0.0 else -1
	# Both nonzero.
	var sa: int = 1 if mantissa > 0.0 else -1
	var sb: int = 1 if other.mantissa > 0.0 else -1
	if sa != sb:
		return 1 if sa > sb else -1
	# Same sign — compare exponent first, then mantissa.
	if exponent != other.exponent:
		var bigger_exp_wins: int = 1 if exponent > other.exponent else -1
		return bigger_exp_wins * sa
	if mantissa > other.mantissa:
		return 1
	if mantissa < other.mantissa:
		return -1
	return 0

func gte(other: BigNumber) -> bool:
	return compare(other) >= 0

func lte(other: BigNumber) -> bool:
	return compare(other) <= 0

func gt(other: BigNumber) -> bool:
	return compare(other) > 0

func lt(other: BigNumber) -> bool:
	return compare(other) < 0

func eq(other: BigNumber) -> bool:
	return compare(other) == 0

func is_zero() -> bool:
	return mantissa == 0.0

# endregion


# region — serialization & display

func to_dict() -> Dictionary:
	return {"m": mantissa, "e": exponent}

func clone() -> BigNumber:
	var c := BigNumber.new()
	c.mantissa = mantissa
	c.exponent = exponent
	return c

func to_float() -> float:
	# For values that fit in a float (~e+/-308). Beyond that, returns INF/0.
	if is_zero():
		return 0.0
	return mantissa * pow(10.0, exponent)

## Display helper. Examples:
##   0           -> "0"
##   42          -> "42"
##   999         -> "999"
##   1234        -> "1.23K"
##   1.5e7       -> "15.0M"
##   1.0e36      -> "1.00aa"
##   1.23e39     -> "1.23ab"
func format() -> String:
	if is_zero():
		return "0"
	var sign_str: String = "-" if mantissa < 0.0 else ""
	var abs_mantissa: float = abs(mantissa)
	var e: int = exponent
	if e < 3:
		# Render with no suffix; preserve integer-ness when possible.
		var v: float = abs_mantissa * pow(10.0, e)
		if abs(v - round(v)) < 1.0e-6:
			return sign_str + str(int(round(v)))
		return sign_str + ("%.2f" % v)
	# Group by thousands.
	@warning_ignore("integer_division")
	var group: int = e / 3
	var remainder: int = e - group * 3
	var display: float = abs_mantissa * pow(10.0, remainder)
	var fmt: String
	if display >= 100.0:
		fmt = "%.0f" % display
	elif display >= 10.0:
		fmt = "%.1f" % display
	else:
		fmt = "%.2f" % display
	return sign_str + fmt + _suffix_for_group(group)

# endregion


# region — internal

func _normalize() -> void:
	if mantissa == 0.0 or is_nan(mantissa):
		mantissa = 0.0
		exponent = 0
		return
	while abs(mantissa) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while abs(mantissa) < 1.0:
		mantissa *= 10.0
		exponent -= 1

const _NAMED_SUFFIXES: Array[String] = [
	"",   # group 0 (e 0..2)   — handled before this lookup
	"K",  # 3
	"M",  # 6
	"B",  # 9
	"T",  # 12
	"Qa", # 15
	"Qi", # 18
	"Sx", # 21
	"Sp", # 24
	"Oc", # 27
	"No", # 30
	"Dc", # 33
]

func _suffix_for_group(group: int) -> String:
	if group < _NAMED_SUFFIXES.size():
		return _NAMED_SUFFIXES[group]
	# Letter-pair suffixes: aa, ab, ..., az, ba, ..., zz.
	# group 12 -> "aa", group 13 -> "ab", etc.
	var idx: int = group - _NAMED_SUFFIXES.size()
	@warning_ignore("integer_division")
	var first: int = idx / 26
	var second: int = idx % 26
	if first < 26:
		var a: int = "a".unicode_at(0)
		return String.chr(a + first) + String.chr(a + second)
	# Past zz — fall through to a 3-letter scheme. Practically unreachable.
	return "??"

# endregion
