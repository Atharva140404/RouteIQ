import pandas as pd
import numpy as np
import random
import uuid
from datetime import datetime, timedelta
import os

random.seed(42)
np.random.seed(42)

# ─────────────────────────────────────────────
# REFERENCE DATA
# ─────────────────────────────────────────────

CITIES_STATES_PINCODES = [
    ("Mumbai",       "Maharashtra",  "400001"),
    ("Mumbai",       "Maharashtra",  "400051"),
    ("Mumbai",       "Maharashtra",  "400069"),
    ("Pune",         "Maharashtra",  "411001"),
    ("Pune",         "Maharashtra",  "411014"),
    ("Nagpur",       "Maharashtra",  "440001"),
    ("Delhi",        "Delhi",        "110001"),
    ("Delhi",        "Delhi",        "110020"),
    ("Delhi",        "Delhi",        "110092"),
    ("Bengaluru",    "Karnataka",    "560001"),
    ("Bengaluru",    "Karnataka",    "560040"),
    ("Bengaluru",    "Karnataka",    "560100"),
    ("Hyderabad",    "Telangana",    "500001"),
    ("Hyderabad",    "Telangana",    "500032"),
    ("Chennai",      "Tamil Nadu",   "600001"),
    ("Chennai",      "Tamil Nadu",   "600020"),
    ("Kolkata",      "West Bengal",  "700001"),
    ("Kolkata",      "West Bengal",  "700046"),
    ("Ahmedabad",    "Gujarat",      "380001"),
    ("Ahmedabad",    "Gujarat",      "380059"),
    ("Jaipur",       "Rajasthan",    "302001"),
    ("Jaipur",       "Rajasthan",    "302017"),
    ("Lucknow",      "Uttar Pradesh","226001"),
    ("Kanpur",       "Uttar Pradesh","208001"),
    ("Patna",        "Bihar",        "800001"),
    ("Bhopal",       "Madhya Pradesh","462001"),
    ("Indore",       "Madhya Pradesh","452001"),
    ("Surat",        "Gujarat",      "395001"),
    ("Vadodara",     "Gujarat",      "390001"),
    ("Coimbatore",   "Tamil Nadu",   "641001"),
]

LOCALITIES = [
    "Andheri West", "Bandra East", "Borivali", "Dadar", "Juhu",
    "Koregaon Park", "Viman Nagar", "Kothrud", "Deccan", "Kalyani Nagar",
    "Indiranagar", "Koramangala", "Whitefield", "Jayanagar", "HSR Layout",
    "Banjara Hills", "Jubilee Hills", "Madhapur", "Gachibowli", "Kondapur",
    "Anna Nagar", "Velachery", "OMR", "Adyar", "T Nagar",
    "Salt Lake", "Park Street", "Behala", "Tollygunge", "New Alipore",
    "Connaught Place", "Lajpat Nagar", "Rohini", "Dwarka", "Karol Bagh",
    "Navrangpura", "Satellite", "Vastrapur", "Bodakdev", "Prahlad Nagar",
    "Malviya Nagar", "Civil Lines", "Mansarovar", "Vaishali Nagar", "Sanganer",
]

STREET_TYPES  = ["Road", "Street", "Marg", "Lane", "Avenue", "Colony", "Nagar", "Chowk"]
BUILDINGS     = ["Sunrise", "Green Valley", "Royal", "Shanti", "Park", "Silver", "Golden", "Blue"]
CORRECTION_TYPES = [
    "Pincode Mismatch", "Spelling Error", "Missing Locality",
    "Duplicate Address", "Incomplete Address", "Wrong City-State",
    "Incorrect House Number", "Missing Landmark", "Street Name Error",
]
CORRECTION_SOURCES = ["AI Model", "Manual Review", "Customer Feedback", "Postal Database", "GPS Verification"]
DELIVERY_ZONES     = ["Zone A", "Zone B", "Zone C", "Zone D", "Zone E"]

SPELLING_ERRORS = {
    "Mumbai":     ["Mumbay", "Mombai", "Mumbei"],
    "Pune":       ["Puna", "Poona", "Puune"],
    "Delhi":      ["Dehli", "Delli", "Delhy"],
    "Bengaluru":  ["Bangalore", "Bangaluru", "Bengalore"],
    "Hyderabad":  ["Hiderabad", "Hydrabad", "Hyderbd"],
    "Chennai":    ["Chenai", "Channai", "Chenni"],
    "Kolkata":    ["Calcutta", "Kolkatta", "Kolkatta"],
    "Ahmedabad":  ["Ahemdabad", "Ahemadabad", "Ahmadabad"],
    "Jaipur":     ["Jaippur", "Jaipar", "Jaipore"],
}

WRONG_STATE_MAP = {
    "Maharashtra": "Gujarat",
    "Karnataka":   "Tamil Nadu",
    "Delhi":       "Uttar Pradesh",
    "Telangana":   "Andhra Pradesh",
    "Tamil Nadu":  "Kerala",
    "West Bengal": "Odisha",
    "Gujarat":     "Rajasthan",
    "Rajasthan":   "Madhya Pradesh",
}

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

def random_pincode():
    return str(random.randint(100000, 999999))

def corrupt_pincode(correct):
    digits = list(correct)
    idx = random.randint(0, 5)
    digits[idx] = str((int(digits[idx]) + random.randint(1, 9)) % 10)
    return "".join(digits)

def make_address(city, locality):
    num   = random.randint(1, 999)
    bldg  = random.choice(BUILDINGS)
    st    = random.choice(STREET_TYPES)
    return f"{num}, {bldg} {st}, {locality}, {city}"

def introduce_error(address, error_type, city, state, pincode):
    if error_type == "Spelling Error":
        if city in SPELLING_ERRORS:
            bad_city = random.choice(SPELLING_ERRORS[city])
            return address.replace(city, bad_city)
        return address.replace("Road", "Raod")

    if error_type == "Missing Locality":
        parts = address.split(", ")
        if len(parts) >= 3:
            parts.pop(1)
        return ", ".join(parts)

    if error_type == "Incomplete Address":
        parts = address.split(", ")
        return ", ".join(parts[:2])

    if error_type == "Wrong City-State":
        wrong_state = WRONG_STATE_MAP.get(state, "Unknown State")
        return address + f" | State: {wrong_state}"

    if error_type == "Incorrect House Number":
        return address.replace(address.split(",")[0], str(random.randint(1000, 9999)))

    if error_type == "Missing Landmark":
        return address + " (no landmark)"

    if error_type == "Street Name Error":
        return address.replace(random.choice(STREET_TYPES), "Rd.")

    return address  # Duplicate / Pincode Mismatch handled at row level

# ─────────────────────────────────────────────
# GENERATE ROWS
# ─────────────────────────────────────────────

def generate_dataset(n=10500):
    rows = []
    start_date = datetime(2024, 1, 1)
    end_date   = datetime(2024, 12, 31)
    date_range = (end_date - start_date).days

    # Pre-generate some duplicate address bases (≈3%)
    duplicate_pool = [
        make_address(c, random.choice(LOCALITIES))
        for c, _, _ in random.choices(CITIES_STATES_PINCODES, k=315)
    ]

    for i in range(n):
        city, state, correct_pincode = random.choice(CITIES_STATES_PINCODES)
        locality  = random.choice(LOCALITIES)
        base_addr = make_address(city, locality)

        correction_required = random.random() < 0.62  # ~62 % need correction
        correction_type     = random.choice(CORRECTION_TYPES) if correction_required else None

        # Build entered address
        if not correction_required:
            entered_address = base_addr
            entered_pincode = correct_pincode
            entered_city    = city
            entered_state   = state
        else:
            if correction_type == "Pincode Mismatch":
                entered_pincode = corrupt_pincode(correct_pincode)
            else:
                entered_pincode = correct_pincode

            if correction_type == "Duplicate Address":
                entered_address = random.choice(duplicate_pool)
            else:
                entered_address = introduce_error(base_addr, correction_type, city, state, correct_pincode)

            entered_city  = city
            entered_state = state
            if correction_type == "Wrong City-State":
                entered_state = WRONG_STATE_MAP.get(state, "Unknown State")

        corrected_address = base_addr  # always the clean version
        correction_source = random.choice(CORRECTION_SOURCES) if correction_required else None

        # Accuracy score: 0-100
        if not correction_required:
            accuracy_score = round(random.uniform(88, 100), 2)
        elif correction_type in ("Pincode Mismatch", "Wrong City-State"):
            accuracy_score = round(random.uniform(30, 60), 2)
        elif correction_type in ("Incomplete Address", "Missing Locality"):
            accuracy_score = round(random.uniform(40, 70), 2)
        else:
            accuracy_score = round(random.uniform(55, 85), 2)

        # Delivery success correlated with accuracy
        if accuracy_score >= 85:
            delivery_success = random.random() < 0.97
        elif accuracy_score >= 65:
            delivery_success = random.random() < 0.80
        elif accuracy_score >= 50:
            delivery_success = random.random() < 0.62
        else:
            delivery_success = random.random() < 0.40

        ts = start_date + timedelta(
            days=random.randint(0, date_range),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59),
        )

        rows.append({
            "order_id":              f"ORD{str(i+1).zfill(6)}",
            "customer_id":           f"CUST{str(random.randint(1, 4000)).zfill(5)}",
            "city":                  entered_city,
            "state":                 entered_state,
            "pincode":               entered_pincode,
            "correct_pincode":       correct_pincode,
            "entered_address":       entered_address,
            "corrected_address":     corrected_address,
            "correction_required":   correction_required,
            "correction_type":       correction_type if correction_type else "None",
            "correction_source":     correction_source if correction_source else "None",
            "delivery_zone":         random.choice(DELIVERY_ZONES),
            "address_accuracy_score":accuracy_score,
            "delivery_success":      delivery_success,
            "correction_timestamp":  ts.strftime("%Y-%m-%d %H:%M:%S"),
            "week_number":           ts.isocalendar()[1],
            "month":                 ts.month,
            "year":                  ts.year,
        })

    df = pd.DataFrame(rows)
    os.makedirs("data", exist_ok=True)
    df.to_csv("data/address_records.csv", index=False)
    print(f"[✓] Generated {len(df):,} records → data/address_records.csv")
    return df

if __name__ == "__main__":
    df = generate_dataset(10500)
    print(df.head(3).to_string())
    print(f"\nShape: {df.shape}")
    print(f"Correction required: {df['correction_required'].sum():,} ({df['correction_required'].mean()*100:.1f}%)")
    print(f"Delivery success   : {df['delivery_success'].sum():,} ({df['delivery_success'].mean()*100:.1f}%)")
