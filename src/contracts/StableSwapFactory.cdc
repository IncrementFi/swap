import SwapConfig from "./SwapConfig.cdc"
import SwapError from "./SwapError.cdc"
import SwapInterfaces from "./SwapInterfaces.cdc"

/**
    Data container of stableswap pair addresses.
    Due to contract upgradability restrictions, some complicated data fields cannot be easily put into the original SwapFactory contract.
    This contract should be deployed under the same account of SwapFactory's
*/
pub contract StableSwapFactory {
    /// All stableswap pairs' address array
    access(self) let stableSwapPairs: [Address]
    /// stableSwapPairMap[token0Identifier][token1Identifier] == stableSwapPairMap[token1Identifier][token0Identifier]
    access(self) let stableSwapPairMap: { String: {String: Address} }
    /// Reserved parameter fields: {ParamName: Value}
    access(self) let _reservedFields: {String: AnyStruct}

    pub fun getPairAddress(token0Key: String, token1Key: String): Address? {
        let pairExist0To1 = self.stableSwapPairMap.containsKey(token0Key) && self.stableSwapPairMap[token0Key]!.containsKey(token1Key)
        let pairExist1To0 = self.stableSwapPairMap.containsKey(token1Key) && self.stableSwapPairMap[token1Key]!.containsKey(token0Key)
        if (pairExist0To1 && pairExist1To0) {
            return self.stableSwapPairMap[token0Key]![token1Key]!
        } else {
            return nil
        }
    }

    pub fun getPairInfo(token0Key: String, token1Key: String): AnyStruct? {
        var pairAddr = self.getPairAddress(token0Key: token0Key, token1Key: token1Key)
        if pairAddr == nil {
            return nil
        }
        return getAccount(pairAddr!).getCapability<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath).borrow()!.getPairInfo()
    }

    pub fun getAllStableSwapPairsLength(): Int {
        return self.stableSwapPairs.length
    }

    /// Get sliced array of pair addresses (inclusive for both indexes)
    pub fun getSlicedPairs(from: UInt64, to: UInt64): [Address] {
        pre {
            from <= to && from < UInt64(self.stableSwapPairs.length):
                SwapError.ErrorEncode(
                    msg: "from index out of range",
                    err: SwapError.ErrorCode.INVALID_PARAMETERS
                )
        }
        let pairLen = UInt64(self.stableSwapPairs.length)
        let endIndex = to >= pairLen ? pairLen - 1 : to
        var curIndex = from
        // Array.slice() is not supported yet.
        let list: [Address] = []
        while curIndex <= endIndex {
            list.append(self.stableSwapPairs[curIndex])
            curIndex = curIndex + 1
        }
        return list
    }

    /// Get sliced array of PairInfos (inclusive for both indexes)
    pub fun getSlicedPairInfos(from: UInt64, to: UInt64): [AnyStruct] {
        let pairSlice: [Address] = self.getSlicedPairs(from: from, to: to)
        var i = 0
        var res: [AnyStruct] = []
        while(i < pairSlice.length) {
            res.append(
                getAccount(pairSlice[i]).getCapability<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath).borrow()!.getPairInfo()
            )
            i = i + 1
        }

        return res
    }

    /// @Param - token0/1Key: type identifier string of the token, e.g.: `A.f8d6e0586b0a20c7.FlowToken`
    /// Can be invoked only within the same account that deploys SwapFactory contract
    access(account) fun addNewPair(token0Key: String, token1Key: String, pairAddress: Address) {
        /// insert pair map
        if (self.stableSwapPairMap.containsKey(token0Key) == false) {
            self.stableSwapPairMap.insert(key: token0Key, {})
        }
        if (self.stableSwapPairMap.containsKey(token1Key) == false) {
            self.stableSwapPairMap.insert(key: token1Key, {})
        }
        self.stableSwapPairMap[token0Key]!.insert(key: token1Key, pairAddress)
        self.stableSwapPairMap[token1Key]!.insert(key: token0Key, pairAddress)
        self.stableSwapPairs.append(pairAddress)
    }

    init() {
        self.stableSwapPairs = []
        self.stableSwapPairMap = {}
        self._reservedFields = {}
    }
}