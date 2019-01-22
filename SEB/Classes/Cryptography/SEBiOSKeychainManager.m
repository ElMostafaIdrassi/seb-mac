//
//  SEBiOSKeychainManager.m
//  SafeExamBrowser
//
//  Created by Daniel R. Schneider on 15/12/15.
//
//

#import "SEBiOSKeychainManager.h"
#import "SEBCryptor.h"
#import "RNCryptor.h"

@implementation SEBiOSKeychainManager

//// We ignore "deprecated" warnings for CSSM methods, since Apple doesn't provide any replacement
//// for asymetric public key cryptography as for OS X 10.10
//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (NSArray*)getIdentitiesAndNames:(NSArray **)names
{
    OSStatus status;
    
    NSDictionary *query = @{
                            (id)kSecClass: (id)kSecClassIdentity,
                            (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                            (id)kSecReturnRef: @YES,
                           };
    CFArrayRef items = NULL;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&items);
    if (status != errSecSuccess) {
        DDLogError(@"Error in %s: SecItemCopyMatching(kSecClassIdentity) returned %@. Can't search keychain, no identities can be read.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        if (items) CFRelease(items);
        return nil;
    }
    NSMutableArray *identities = [NSMutableArray arrayWithArray:(__bridge  NSArray*)(items)];
    if (items) CFRelease(items);
    NSMutableArray *identitiesNames = [NSMutableArray arrayWithCapacity:[identities count]];
    
    CFStringRef commonName;
    SecCertificateRef certificateRef;
    SecKeyRef publicKeyRef;
    SecKeyRef privateKeyRef;
    CFArrayRef emailAddressesRef;
    NSString *identityName;
    NSUInteger count = [identities count];
    for (NSUInteger i=0; i<count; i++) {
        SecIdentityRef identityRef = (__bridge SecIdentityRef)[identities objectAtIndex:i];
        if (SecIdentityCopyCertificate(identityRef, &certificateRef) == noErr) {
            if (SecIdentityCopyPrivateKey(identityRef, &privateKeyRef) == noErr) {
                if ((publicKeyRef = SecCertificateCopyPublicKey(certificateRef))) {
                    if ((status = SecCertificateCopyCommonName(certificateRef, &commonName)) == noErr) {
                        if ((status = SecCertificateCopyEmailAddresses(certificateRef, &emailAddressesRef)) == noErr) {
                            identityName = [NSString stringWithFormat:@"%@%@",
                                            (__bridge NSString *)commonName ?
                                            [NSString stringWithFormat:@"%@ ",(__bridge NSString *)commonName] :
                                            @"" ,
                                            CFArrayGetCount(emailAddressesRef) ?
                                            (__bridge NSString *)CFArrayGetValueAtIndex(emailAddressesRef, 0) :
                                            @""];
                            // Check if there is already an identitiy with the identical name (can happen)
                            if ([identitiesNames containsObject:identityName]) {
                                // If yes, we need to make the name unique; we add the public key hash
                                // Get public key hash from selected identity's certificate
                                NSData* publicKeyHash = [self getPublicKeyHashFromCertificate:certificateRef];
                                if (!publicKeyHash) {
                                    DDLogError(@"Error in %s: Could not get public key hash form certificate. Generated a random hash.", __FUNCTION__);
                                    // If the hash couldn't be determinded (what actually shouldn't happen): Create random data instead
                                    publicKeyHash = [RNCryptor randomDataOfLength:20];
                                }
                                unsigned char hashedChars[20];
                                [publicKeyHash getBytes:hashedChars length:20];
                                NSMutableString* hashedString = [NSMutableString new];
                                for (int i = 0 ; i < 20 ; ++i) {
                                    [hashedString appendFormat: @"%02x", hashedChars[i]];
                                }
                                [identitiesNames addObject:[NSString stringWithFormat:@"%@ %@",identityName, hashedString]];
                            } else {
                                [identitiesNames addObject:identityName];
                            }
                            
                            DDLogDebug(@"Common name: %@ %@", (__bridge NSString *)commonName ? (__bridge NSString *)commonName : @"" , CFArrayGetCount(emailAddressesRef) ? (__bridge NSString *)CFArrayGetValueAtIndex(emailAddressesRef, 0) : @"");
                            DDLogDebug(@"Public key can be used for encryption, private key can be used for decryption");
                            if (emailAddressesRef) CFRelease(emailAddressesRef);
                            if (commonName) CFRelease(commonName);
                            if (publicKeyRef) CFRelease(publicKeyRef);
                            if (privateKeyRef) CFRelease(privateKeyRef);
                            if (certificateRef) CFRelease(certificateRef);
                            // Continue with next element
                            continue;
                            
                        } else {
                            DDLogError(@"Error in %s: SecCertificateCopyEmailAddresses returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
                        }
                        if (commonName) {
                            CFRelease(commonName);
                        }
                    } else {
                        DDLogError(@"Error in %s: SecCertificateCopyCommonName returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
                    }
                    if (publicKeyRef) {
                        CFRelease(publicKeyRef);
                    }
                } else {
                    DDLogError(@"Error in %s: SecCertificateCopyPublicKey returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
                }
                if (privateKeyRef) {
                    CFRelease(privateKeyRef);
                }
            } else {
                DDLogError(@"Error in %s: SecIdentityCopyPrivateKey returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
            }
            if (certificateRef) {
                CFRelease(certificateRef);
            }
        } else {
            DDLogError(@"Error in %s: SecIdentityCopyCertificate returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        }
        
        // Currently iterated identity cannot be used: remove it from the list
        [identities removeObjectAtIndex:i];
        i--;
        count--;
    }
    NSArray *foundIdentities;
    foundIdentities = [NSArray arrayWithArray:identities];
    // return array of identity names
    if (names) {
        *names = [NSArray arrayWithArray:identitiesNames];
    }
    return foundIdentities; // items contains all SecIdentityRefs in keychain
}


- (NSArray*)getCertificatesAndNames:(NSArray **)names
{
    OSStatus status;
    
    NSDictionary *query = @{
                            (id)kSecClass: (id)kSecClassCertificate,
                            (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                            (id)kSecReturnRef: @YES,
                            };
    CFTypeRef items = NULL;
    
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&items);
    if (status != errSecSuccess) {
        DDLogError(@"Error in %s: SecItemCopyMatching(kSecClassIdentity) returned %@. Can't search keychain, no identities can be read.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        if (items) CFRelease(items);
        return nil;
    }
    
    NSMutableArray *certificates = [NSMutableArray arrayWithArray:(__bridge_transfer NSArray*)(items)];
    NSMutableArray *certificatesNames = [NSMutableArray arrayWithCapacity:[certificates count]];
    
    CFStringRef commonName = NULL;
    CFArrayRef emailAddressesRef = NULL;
    NSString *certificateName;
    NSUInteger i, count = [certificates count];
    for (i=0; i<count; i++) {
        SecCertificateRef certificateRef = (__bridge SecCertificateRef)[certificates objectAtIndex:i];
        if ((status = SecCertificateCopyCommonName(certificateRef, &commonName)) == noErr) {
            
            if ((status = SecCertificateCopyEmailAddresses(certificateRef, &emailAddressesRef)) == noErr) {

                certificateName = [NSString stringWithFormat:@"%@",
                                   (__bridge NSString *)commonName ?
                                   //There is a commonName: just take that as a name
                                   [NSString stringWithFormat:@"%@ ",(__bridge NSString *)commonName] :
                                   //there is no common name: take the e-mail address (if it exists)
                                   CFArrayGetCount(emailAddressesRef) ?
                                   (__bridge NSString *)CFArrayGetValueAtIndex(emailAddressesRef, 0) :
                                   @""];
                if ([certificateName isEqualToString:@""] || [certificatesNames containsObject:certificateName]) {
                    //get public key hash from selected identity's certificate
                    NSData* publicKeyHash = [self getPublicKeyHashFromCertificate:certificateRef];
                    if (!publicKeyHash) {
                        DDLogError(@"Error in %s: Could not get public key hash form certificate. Generated a random hash.", __FUNCTION__);
                        // If the hash couldn't be determinded (what actually shouldn't happen): Create random data instead
                        publicKeyHash = [RNCryptor randomDataOfLength:20];
                    }
                    unsigned char hashedChars[20];
                    [publicKeyHash getBytes:hashedChars length:20];
                    NSMutableString* hashedString = [NSMutableString new];
                    for (int i = 0 ; i < 20 ; ++i) {
                        [hashedString appendFormat: @"%02x", hashedChars[i]];
                    }
                    [certificatesNames addObject:[NSString stringWithFormat:@"%@ %@",certificateName, hashedString]];
                } else {
                    [certificatesNames addObject:certificateName];
                }
                DDLogDebug(@"Common name: %@ %@", (__bridge NSString *)commonName ? (__bridge NSString *)commonName : @"" , CFArrayGetCount(emailAddressesRef) ? (__bridge NSString *)CFArrayGetValueAtIndex(emailAddressesRef, 0) : @"");
                
                if (commonName) CFRelease(commonName);
                if (emailAddressesRef) CFRelease(emailAddressesRef);
                
                continue;

            } else {
                DDLogError(@"Error in %s: SecCertificateCopyEmailAddresses returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
            }
            if (commonName) CFRelease(commonName);
        } else {
            DDLogError(@"Error in %s: SecCertificateCopyCommonName returned %@. This identity will be skipped.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        }
        // Currently iterated certificate cannot be used: remove it from the list
        [certificates removeObjectAtIndex:i];
        i--;
        count--;
    }
    NSArray *foundCertificates;
    foundCertificates = [NSArray arrayWithArray:certificates];
    // return array of identity names
    if (names) {
        *names = [NSArray arrayWithArray:certificatesNames];
    }
    return foundCertificates; // items contains all SecIdentityRefs in keychain
}


- (NSData*)getPublicKeyHashFromCertificate:(SecCertificateRef)certificate
{
    SecKeyRef publicKeyRef = [self copyPublicKeyFromCertificate:certificate];
    
//    CFTypeRef publicKeyResult = NULL;
//    OSStatus status;
//    NSDictionary *query = @{
//                            (id)kSecClass: (id)kSecClassKey,
//                            (id)kSecValueRef: (__bridge id)publicKeyRef,
//                            (id)kSecReturnData: @YES,
//                            };
//    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&publicKeyResult);
    
    CFErrorRef error = NULL;
    NSData *publicKeyData = (NSData*)CFBridgingRelease(  // ARC takes ownership
                                                 SecKeyCopyExternalRepresentation(publicKeyRef, &error)
                                                 );
    if (publicKeyRef) CFRelease(publicKeyRef);
    if (!publicKeyData) {
        DDLogError(@"Could not extract public key data:  %@", error);
        return nil;
    }
    
    NSData *publicKeyHash = [self generateSHA1HashForData:publicKeyData];

//    if (status !=errSecSuccess) {
//        DDLogError(@"Could not extract public key data:  %@", [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
//        if (publicKeyResult) CFRelease(publicKeyResult);
//        return nil;
//    }
//    NSData *publicKeyData = (NSData *)CFBridgingRelease(publicKeyResult);
    return publicKeyHash;
}


- (NSData*) generateSHA1HashForData:(NSData *)inputData {
    unsigned char hashedChars[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(inputData.bytes,
              (uint)inputData.length,
              hashedChars);
    NSData *hashedData = [NSData dataWithBytes:hashedChars length:CC_SHA1_DIGEST_LENGTH];
    return hashedData;
}


- (SecKeyRef)getPrivateKeyFromPublicKeyHash:(NSData*)publicKeyHash
{
    SecIdentityRef identityRef = [self getIdentityRefFromPublicKeyHash:publicKeyHash];
    if (!identityRef) {
        return NULL;
    }
    SecKeyRef privateKeyRef = nil;
    OSStatus status = SecIdentityCopyPrivateKey(identityRef, &privateKeyRef);
    if (status != errSecSuccess) {
        DDLogError(@"No associated private key found for public key hash.");
        if (privateKeyRef) CFRelease(privateKeyRef);
        return NULL;
    }
    return privateKeyRef;
}


- (SecIdentityRef)getIdentityRefFromPublicKeyHash:(NSData*)publicKeyHash
{
    OSStatus status;
    NSDictionary *query = @{
                            (id)kSecClass: (id)kSecClassIdentity,
                            (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                            (id)kSecReturnRef: @YES,
                            };
    CFArrayRef items = NULL;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&items);
    if (status != errSecSuccess) {
        DDLogError(@"Error in %s: SecItemCopyMatching(kSecClassIdentity) returned %@. Can't search keychain, no identities can be read.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        if (items) CFRelease(items);
        return NULL;
    }
    NSArray *identities = (__bridge  NSArray*)(items);
    if (items) CFRelease(items);
    
    SecIdentityRef identityRef = NULL;
    SecCertificateRef certificateRef;
    for (id keychainIdentity in identities) {
        status = SecIdentityCopyCertificate((SecIdentityRef)keychainIdentity, &certificateRef);
        if (status == errSecSuccess) {
            NSData *keychainIdentityPublicKeyHash = [self getPublicKeyHashFromCertificate:certificateRef];
            if ([keychainIdentityPublicKeyHash isEqualToData:publicKeyHash]) {
                identityRef = (SecIdentityRef)CFBridgingRetain(keychainIdentity);
            }
        }
    }
    if (identityRef == NULL) {
        DDLogError(@"No associated identity found for certificate.");
        return NULL;
    }
    return identityRef;
}


- (SecKeyRef)copyPrivateKeyRefFromIdentityRef:(SecIdentityRef)identityRef
{
    SecKeyRef privateKeyRef = nil;
    OSStatus status = SecIdentityCopyPrivateKey(identityRef, &privateKeyRef);
    if (status != errSecSuccess) {
        DDLogError(@"No associated private key found for identity.");
        if (privateKeyRef) CFRelease(privateKeyRef);
        return NULL;
    }
    return privateKeyRef;
}


- (SecKeyRef)copyPublicKeyFromCertificate:(SecCertificateRef)certificate {
        SecKeyRef key = SecCertificateCopyPublicKey(certificate);
        if (key == NULL) {
            DDLogError(@"No proper public key found in certificate.");
            if (key) CFRelease(key);
            return NULL;
        }
        return key; // public key contained in certificate
}


- (SecIdentityRef)createIdentityWithCertificate:(SecCertificateRef)certificate
{
    OSStatus status;
    
    NSDictionary *query = @{
                            (id)kSecClass: (id)kSecClassIdentity,
                            (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                            (id)kSecReturnRef: @YES,
                            };
    CFArrayRef items = NULL;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&items);
    if (status != errSecSuccess) {
        DDLogError(@"Error in %s: SecItemCopyMatching(kSecClassIdentity) returned %@. Can't search keychain, no identities can be read.", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
        if (items) CFRelease(items);
        return NULL;
    }
    NSArray *identities = (__bridge  NSArray*)(items);
    if (items) CFRelease(items);

    SecIdentityRef identityRef = NULL;
    SecCertificateRef certificateRef;
    for (id keychainIdentity in identities) {
        status = SecIdentityCopyCertificate((SecIdentityRef)keychainIdentity, &certificateRef);
        if (status == errSecSuccess && certificateRef == certificate) {
            identityRef = (__bridge SecIdentityRef)keychainIdentity;
        }
    }
    if (identityRef == NULL) {
        DDLogError(@"No associated identity found for certificate.");
        return NULL;
    }
    return identityRef;
}


- (SecCertificateRef)copyCertificateFromIdentity:(SecIdentityRef)identityRef
{
    SecCertificateRef certificateRef;
    OSStatus status = SecIdentityCopyCertificate(identityRef, &certificateRef);
    if (status != errSecSuccess) {
        DDLogError(@"No certificate found for identity.");
        if (certificateRef) CFRelease(certificateRef);
        return NULL;
    }
    return certificateRef;
}


- (NSData*)getDataForCertificate:(SecCertificateRef)certificate {
    //
    //    SecItemImportExportKeyParameters keyParams;
    //
    //    NSString *password = userDefaultsMasala;
    //
    //    keyParams.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    //    keyParams.flags = 0;
    //    keyParams.passphrase = (__bridge CFTypeRef)(password);
    ////    keyParams.passphrase = NULL;
    //    keyParams.alertTitle = NULL;
    //    keyParams.alertPrompt = NULL;
    //    keyParams.accessRef = NULL;
    //    // These two values are for import
    //    keyParams.keyUsage = NULL;
    //    keyParams.keyAttributes = NULL;
    //
    //    CFDataRef exportedData = NULL;
    //
    //    OSStatus success = SecItemExport (
    //                                      certificate,
    ////                                      kSecFormatNetscapeCertSequence,
    //                                      kSecFormatPKCS12,
    //                                      0,
    //                                      &keyParams,
    //                                      &exportedData
    //                                      );
    //
    //    if (success == errSecSuccess) {
    //        return (NSData*)CFBridgingRelease(exportedData);
    //    } else {
    //        DDLogError(@"Error in %s: SecItemImport of embedded certificate failed %@", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:success userInfo:NULL]);
    //        if (exportedData) CFRelease(exportedData);
    //        return nil;
    //    }
    return nil;
}


- (BOOL)importCertificateFromData:(NSData*)certificateData {
    //
    //    SecItemImportExportKeyParameters keyParams;
    //
    //    NSString *password = userDefaultsMasala;
    //
    //    keyParams.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    //    keyParams.flags = 0;
    //    keyParams.passphrase = (__bridge CFTypeRef)(password);
    ////    keyParams.passphrase = NULL;
    //    keyParams.alertTitle = NULL;
    //    keyParams.alertPrompt = NULL;
    //    keyParams.accessRef = NULL;
    //    // These two values are for import
    ////    keyParams.keyUsage = (__bridge CFArrayRef)[NSArray arrayWithObjects:(__bridge id)(kSecAttrCanSign), (__bridge id)(kSecAttrCanWrap), nil];
    //    keyParams.keyUsage = NULL;
    //    keyParams.keyAttributes = NULL;
    //
    //    SecExternalItemType itemType = kSecItemTypeUnknown;
    ////    SecExternalFormat externalFormat = kSecFormatPEMSequence;
    ////    SecExternalItemType itemType = kSecItemTypeCertificate;
    ////    SecExternalFormat externalFormat = kSecFormatX509Cert;
    ////    SecExternalItemType itemType = kSecItemTypeAggregate;
    //    SecExternalFormat externalFormat = kSecFormatPKCS12;
    ////    SecExternalFormat externalFormat = kSecFormatUnknown;
    ////    SecExternalFormat externalFormat = kSecFormatPKCS7;
    //    int flags = 0;
    //
    //    SecKeychainRef keychain;
    //    SecKeychainCopyDefault(&keychain);
    //
    //    CFArrayRef outItems;
    //
    //    OSStatus status = SecItemImport((__bridge CFDataRef)certificateData,
    ////                                    (__bridge CFStringRef)@".cert", // filename or extension
    //                                    NULL, // filename or extension
    //                                   &externalFormat, // See SecExternalFormat for details
    //                                   &itemType, // item type
    //                                   flags, // See SecItemImportExportFlags for details
    //                                   &keyParams,
    //                                   keychain, // Don't import into a keychain
    //                                   &outItems);
    //    if (keychain) CFRelease(keychain);
    //    if (status != noErr) {
    //        if (status == errKCDuplicateItem) {
    //            DDLogWarn(@"%s: SecItemImport of embedded certificate failed, because it is already in the keychain.", __FUNCTION__);
    //        } else {
    //            DDLogError(@"Error in %s: SecItemImport of embedded certificate failed %@", __FUNCTION__, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:NULL]);
    //        }
    //        return NO;
    //    }
    //    return YES;
    return NO;
}


- (NSData*)getDataForIdentity:(SecIdentityRef)identity {
    //
    //    SecItemImportExportKeyParameters keyParams;
    //
    //    NSString *password = userDefaultsMasala;
    //
    //    keyParams.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    //    keyParams.flags = 0;
    //    keyParams.passphrase = (__bridge CFTypeRef)(password);
    //    keyParams.alertTitle = NULL;
    //    keyParams.alertPrompt = NULL;
    //    keyParams.accessRef = NULL;
    //    // These two values are for import
    //    keyParams.keyUsage = NULL;
    //    keyParams.keyAttributes = NULL;
    //
    //    CFDataRef exportedData = NULL;
    //
    //    OSStatus success = SecItemExport (
    //                            identity,
    //                            kSecFormatPKCS12,
    //                            0,
    //                            &keyParams,
    //                            &exportedData
    //                            );
    //
    //    if (success == errSecSuccess) return (NSData*)CFBridgingRelease(exportedData); else return nil;
    return nil;
}


- (BOOL) importIdentityFromData:(NSData*)identityData {
    
    NSString *password = userDefaultsMasala;
    NSDictionary* options = @{ (id)kSecImportExportPassphrase : password };
    
    CFArrayRef rawItems = NULL;
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)identityData,
                                      (__bridge CFDictionaryRef)options,
                                      &rawItems);

    NSArray* items = (NSArray*)CFBridgingRelease(rawItems); // Transfer to ARC
    NSDictionary* firstItem = nil;
    if ((status == errSecSuccess) && ([items count]>0)) {
        firstItem = items[0];
    } else {
        DDLogError(@"Importing an identity from PKCS12 data using SecItemImport failed (oserr=%d)\n", status);
        return NO;
    }

    SecIdentityRef identity =
    (SecIdentityRef)CFBridgingRetain(firstItem[(id)kSecImportItemIdentity]);

    NSDictionary* addQuery = @{ (id)kSecValueRef:   (__bridge id)identity,
//                                (id)kSecClass:      (id)kSecClassCertificate,
                                (id)kSecAttrLabel:  SEBFullAppName,
                                };

    status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    if (status != errSecSuccess) {
        DDLogError(@"Adding an identity to the Keychain using SecItemAdd failed (oserr=%d)\n", status);
        return NO;
    }
    
    return YES;
}


- (NSData*)encryptData:(NSData*)plainData withPublicKeyFromCertificate:(SecCertificateRef)certificate {
    //    //- (NSData*)encryptData:(NSData*)inputData withPublicKey:(SecKeyRef*)publicKey {
    //    SecKeyRef publicKeyRef = NULL;
    //    OSStatus status = SecCertificateCopyPublicKey(certificate, &publicKeyRef);
    //    if (status != errSecSuccess) {
    //            DDLogError(@"No public key found in certificate.");
    //            if (publicKeyRef) CFRelease(publicKeyRef);
    //            return nil;
    //    }
    //
    //    CSSM_RETURN crtn;
    //    CSSM_DATA		ptext;
    //    CSSM_DATA		ctext;
    //
    //    ptext.Data = (uint8 *)[plainData bytes];
    //    ptext.Length = [plainData length];
    //    ctext.Data = NULL;
    //    ctext.Length = 0;
    //
    //    const CSSM_ACCESS_CREDENTIALS *creds;
    //    status = SecKeyGetCredentials(publicKeyRef,
    //                                  CSSM_ACL_AUTHORIZATION_ENCRYPT,
    //                                  kSecCredentialTypeWithUI,
    //                                  &creds);
    //
    //    const CSSM_KEY *pubKey;
    //
    //    CSSM_CSP_HANDLE cspHandle;
    //    status = SecKeyGetCSPHandle(publicKeyRef, &cspHandle);
    //
    //    status = SecKeyGetCSSMKey(publicKeyRef, &pubKey);
    //    /*assert(pubKey->KeyHeader.AlgorithmId ==
    //           CSSM_ALGID_RSA);
    //    assert(pubKey->KeyHeader.KeyClass ==
    //           CSSM_KEYCLASS_PUBLIC_KEY);
    //    assert(pubKey->KeyHeader.KeyUsage ==
    //           CSSM_KEYUSE_ENCRYPT ||
    //           pubKey->KeyHeader.KeyUsage ==
    //           CSSM_KEYUSE_ANY);*/
    //
    //    CSSM_CC_HANDLE  ccHandle;
    //    crtn = CSSM_CSP_CreateAsymmetricContext(cspHandle,
    //                                            CSSM_ALGID_RSA,
    //                                            creds, pubKey,
    //                                            CSSM_PADDING_PKCS1, &ccHandle);
    //    cssmPerror("encrypt context", crtn);
    //    assert(crtn == CSSM_OK);
    //
    //    CSSM_SIZE       bytesEncrypted;
    //    CSSM_DATA       remData = {0, NULL};
    //    crtn = CSSM_EncryptData(ccHandle, &ptext, 1,
    //                            &ctext, 1, &bytesEncrypted, &remData);
    //    cssmPerror("encryptdata", crtn);
    //    assert(crtn == CSSM_OK);
    //    CSSM_DeleteContext(ccHandle);
    //
    //    NSData *cipherData = [NSData dataWithBytes:ctext.Data length:ctext.Length];
    //
    //    if (publicKeyRef) CFRelease(publicKeyRef);
    //    free(ctext.Data);
    //    return cipherData;
    //    //[cipherData encodeBase64ForData];
    return nil;
}


- (NSData*)decryptData:(NSData*)cipherData withPrivateKey:(SecKeyRef)privateKeyRef
{
    size_t blockSize = SecKeyGetBlockSize(privateKeyRef);
    uint8_t *buffer = calloc(blockSize, sizeof(uint8_t));
    
    NSMutableData *plainData = [NSMutableData new];
    for (NSUInteger i = 0; i < [cipherData length]; i += blockSize) {
        NSData *subCipherText = [cipherData subdataWithRange:NSMakeRange(i, MIN(blockSize, [cipherData length] - i))];
        size_t plainTextLen = blockSize;
        
        OSStatus status = SecKeyDecrypt(privateKeyRef, kSecPaddingPKCS1, [subCipherText bytes], [subCipherText length], buffer, &plainTextLen);
        if (status != errSecSuccess) {
            DDLogError(@"Decrypting data using private key failed! (oserr=%d)\n", status);
            free(buffer);
            return nil;
        }
        [plainData appendBytes:buffer length:plainTextLen];
    }
    free(buffer);
    
    if (privateKeyRef) {
        CFRelease(privateKeyRef);
    }
    return plainData;
}

// Switch diagnostics for "deprecated" on again
//#pragma clang diagnostic pop

@end
