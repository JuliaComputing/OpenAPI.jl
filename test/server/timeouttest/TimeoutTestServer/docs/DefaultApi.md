# DefaultApi

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delayresponse_get**](DefaultApi.md#delayresponse_get) | **GET** /delayresponse | Delay Response Endpoint


# **delayresponse_get**
> delayresponse_get(req::HTTP.Request, delay_seconds::Int64;) -> DelayresponseGet200Response

Delay Response Endpoint

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **req** | **HTTP.Request** | The HTTP Request object | 
**delay_seconds** | **Int64**| Number of seconds to delay the response | [default to nothing]

### Return type

[**DelayresponseGet200Response**](DelayresponseGet200Response.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

