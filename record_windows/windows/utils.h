#pragma once

#include <memory>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <tchar.h>
#include <comdef.h>
#include <system_error>

using namespace flutter;

//////////////////////////////////////////////////////////////////////////
//  Flutter method arguments
//////////////////////////////////////////////////////////////////////////
template <typename T>
T GetArgument(const std::string arg, const EncodableValue* args, T fallback) {
	T result{ fallback };
	const auto* arguments = std::get_if<EncodableMap>(args);
	if (arguments) {
		auto result_it = arguments->find(EncodableValue(arg));
		if (result_it != arguments->end()) {
			if (!result_it->second.IsNull())
				result = std::get<T>(result_it->second);
		}
	}
	return result;
}

template <typename T>
static bool GetValueFromEncodableMap(const flutter::EncodableMap* map,
	const char* key, T& out) {
	auto iter = map->find(flutter::EncodableValue(key));
	if (iter != map->end() && !iter->second.IsNull()) {
		if (auto* value = std::get_if<T>(&iter->second)) {
			out = *value;
			return true;
		}
	}
	return false;
}

//////////////////////////////////////////////////////////////////////////
//  COM Safe release
//////////////////////////////////////////////////////////////////////////

template <class T> void SafeRelease(T** ppT)
{
	if (*ppT)
	{
		(*ppT)->Release();
		*ppT = NULL;
	}
}

template <class T> inline void SafeRelease(T*& pT)
{
	if (pT != NULL)
	{
		pT->Release();
		pT = NULL;
	}
}

inline std::string toString(LPCWSTR pwsz) {
	int cch = WideCharToMultiByte(CP_UTF8, 0, pwsz, -1, 0, 0, NULL, NULL);

	char* psz = new char[cch];

	WideCharToMultiByte(CP_UTF8, 0, pwsz, -1, psz, cch, NULL, NULL);

	std::string st(psz);
	delete[] psz;

	return st;
}

inline std::string Utf8FromUtf16(const std::wstring& utf16_string) {
	if (utf16_string.empty()) {
		return std::string();
	}
	int target_length = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string.data(), static_cast<int>(utf16_string.length()), nullptr, 0, nullptr, nullptr);

	std::string utf8_string;
	if (target_length == 0 || target_length > utf8_string.max_size()) {
		return utf8_string;
	}

	utf8_string.resize(target_length);
	int converted_length = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string.data(), static_cast<int>(utf16_string.length()), utf8_string.data(), target_length, nullptr, nullptr);
	if (converted_length == 0) {
		return std::string();
	}

	return utf8_string;
}


//////////////////////////////////////////////////////////////////////////
//  CritSec
//  Description: Wraps a critical section.
//////////////////////////////////////////////////////////////////////////

class CritSec
{
private:
	CRITICAL_SECTION m_criticalSection;
public:
	CritSec()
	{
		InitializeCriticalSection(&m_criticalSection);
	}

	~CritSec()
	{
		DeleteCriticalSection(&m_criticalSection);
	}

	void Lock()
	{
		EnterCriticalSection(&m_criticalSection);
	}

	void Unlock()
	{
		LeaveCriticalSection(&m_criticalSection);
	}
};


//////////////////////////////////////////////////////////////////////////
//  AutoLock
//  Description: Provides automatic locking and unlocking of a 
//               of a critical section.
//
//  Note: The AutoLock object must go out of scope before the CritSec.
//////////////////////////////////////////////////////////////////////////

class AutoLock
{
private:
	CritSec* m_pCriticalSection;
public:
	AutoLock(CritSec& crit)
	{
		m_pCriticalSection = &crit;
		m_pCriticalSection->Lock();
	}
	~AutoLock()
	{
		m_pCriticalSection->Unlock();
	}
};
