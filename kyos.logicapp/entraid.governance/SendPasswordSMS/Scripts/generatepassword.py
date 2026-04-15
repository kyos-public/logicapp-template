#!/usr/bin/env python3
"""
Azure Automation Runbook: Password Generator
Generates random passwords with optional Entra ID compatibility
"""
import secrets
import string
import sys

def generate_password(length=20, entra_compatible=False):
    """
    Generate a random password of specified length.
    
    Args:
        length: Length of the password (default: 20)
        entra_compatible: If True, excludes characters forbidden in Entra ID
    
    Returns:
        A randomly generated password string
    """
    if entra_compatible:
        # Entra ID forbidden characters: @ # $ % ^ & * - _ ! + = [ ] { } | \ : ' , . ? / ~ " ( ) ; `
        # Use only letters and digits for Entra compatibility
        alphabet = string.ascii_letters + string.digits
    else:
        # Use full character set
        alphabet = string.ascii_letters + string.digits + string.punctuation
    
    # Guarantee at least one digit, then fill the rest from the full alphabet
    chars = [secrets.choice(string.digits)]
    chars += [secrets.choice(alphabet) for _ in range(length - 1)]
    secrets.SystemRandom().shuffle(chars)
    password = ''.join(chars)
    return password

# Azure Automation Runbook Parameters
# When creating the runbook, define these parameters in the Azure portal:
# - EntraCompatibility (String, optional, default: "")
# - Length (String, optional, default: "20")

def convert_to_bool(value):
    """Convert various input types to boolean"""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ['true', '1', 'yes', '-e', 'y']
    return bool(value)

# Main execution
EntraCompatibility = ""
Length = "20"

# Parse parameters (works for both Azure Automation and command line)
if len(sys.argv) > 1:
    for i, arg in enumerate(sys.argv[1:], 1):
        if i == 1:  # First parameter
            EntraCompatibility = arg
        elif i == 2:  # Second parameter
            Length = arg

# Process parameters
entra_compatible = convert_to_bool(EntraCompatibility)
length = int(Length) if Length and Length.isdigit() else 20

# Generate and output password
password = generate_password(length, entra_compatible)
sys.stdout.write(password)
sys.stdout.flush()