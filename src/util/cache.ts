/***********************************************************
* This file is part of the Slock.it IoT Layer.             *
* The Slock.it IoT Layer contains:                         *
*   - USN (Universal Sharing Network)                      *
*   - INCUBED (Trustless INcentivized remote Node Network) *
************************************************************
* Copyright (C) 2016 - 2018 Slock.it GmbH                  *
* All Rights Reserved.                                     *
************************************************************
* You may use, distribute and modify this code under the   *
* terms of the license contract you have concluded with    *
* Slock.it GmbH.                                           *
* For information about liability, maintenance etc. also   *
* refer to the contract concluded with Slock.it GmbH.      *
************************************************************
* For more information, please refer to https://slock.it   *
* For questions, please contact info@slock.it              *
***********************************************************/

import { RPCRequest, RPCResponse, util } from "in3"


export class SimpleCache {

  data: Map<string, RPCResponse>



  constructor() {
    this.data = new Map()
  }
  //  nl.proof.signatures = await collectSignatures(this, signers, [{ blockNumber: nl.lastBlockNumber }], verifiedHashes)

  put(key: string, response: RPCResponse): RPCResponse {
    this.data.set(key, response)
    return response
  }

  clear() {
    this.data.clear()
  }

  async getFromCache(request: RPCRequest,
    fallBackHandler: (request: RPCRequest) => Promise<RPCResponse>,
    collectSignature: (signers: string[], blockNumbers: number[], verifiedHashes: string[]) => any): Promise<RPCResponse> {
    const key = getKey(request)
    const res = this.data.get(key)
    if (res) {
      const r: RPCResponse = { ...res, id: request.id }
      if (request.in3 && r.in3 && r.in3.proof) {
        if (!request.in3.signatures || request.in3.signatures.length === 0) {
          if (r.in3 && r.in3.proof && r.in3.proof.signatures)
            delete r.in3.proof.signatures
          return r
        }
        else {
          // TODO use a signature cache
          const oldSignatures = r.in3.proof && r.in3.proof.signatures
          const blockNumbers = oldSignatures && oldSignatures.map(_ => _.block).filter((_, i, a) => _ && a.indexOf(_) === i)
          if (!blockNumbers || !blockNumbers.length)
            return this.put(key, await fallBackHandler(request))

          r.in3 = {
            ...r.in3,
            proof: {
              ...r.in3.proof,
              signatures: await collectSignature(request.in3.signatures, blockNumbers, request.in3.verifiedHashes || [])
            }
          }
        }
      }
      return r
    }
    return this.put(key, await fallBackHandler(request))
  }

}


function getKey(request: RPCRequest) {
  return request.method + ':' + JSON.stringify(request.params) + '-' + request.in3 ? (
    [request.in3.chainId, request.in3.includeCode, request.in3.verification, request.in3.verifiedHashes].map(_ => _ || '').join('|')
  ) : ''
}