#!/usr/bin/env python3
import secrets
import string
alphabet = string.ascii_letters + string.digits + string.punctuation
password = ''.join(secrets.choice(alphabet) for i in range(20)) 

print(password)